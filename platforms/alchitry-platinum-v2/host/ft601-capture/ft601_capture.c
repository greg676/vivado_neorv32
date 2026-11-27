/*
 * FT601 LA triggered capture dump (FTDI D3XX).
 *
 * Writes a START/STOP command, then reads a LAT3 header (trigger position,
 * overflow/drop counts) plus packed 8-bit samples.
 *
 * Build:
 *   make              -> packer + header self-test (no SDK)
 *   make d3xx         -> hardware tool (needs D3XX SDK)
 */

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifndef FT601_NO_D3XX
#include "ftd3xx.h"
#endif

#define PIPE_OUT 0x02
#define PIPE_IN  0x82
#define WORD_SIZE 4u
#define HDR_WORDS 8u
#define HDR_BYTES (HDR_WORDS * WORD_SIZE)
#define LAT3_MAGIC 0x3354414Cu
#define LAT3_VERSION 1u

#define CMD_NOP   0u
#define CMD_CFG   1u
#define CMD_START 2u
#define CMD_STOP  3u
#define CMD_FORCE 4u

#define EDGE_RISE 0u
#define EDGE_FALL 1u
#define EDGE_BOTH 2u
#define EDGE_IMM  3u

#define SRC_COUNTER 0
#define SRC_WALKING 1

typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t status;
    uint32_t nsamples;
    uint32_t trig_pos;
    uint32_t overflow;
    uint32_t drop;
    uint32_t post_cfg;
    unsigned source;
    unsigned channel;
    unsigned edge;
    int triggered;
    int aborted;
    int immediate;
} lat3_header;

typedef struct {
    uint64_t words_ok;
    uint64_t words_bad;
    uint64_t first_bad_index;
    uint32_t first_bad_got;
    uint32_t first_bad_exp;
    uint64_t bytes_odd;
} verify_stats;

static uint32_t make_cmd(unsigned cmd, unsigned src, unsigned ch, unsigned edge,
                         unsigned post)
{
    return (cmd & 0xFu) | ((src & 3u) << 4) | ((ch & 7u) << 6) |
           ((edge & 3u) << 9) | ((post & 0xFFFFu) << 16);
}

static int parse_header(const uint32_t *w, lat3_header *h)
{
    memset(h, 0, sizeof(*h));
    h->magic = w[0];
    h->version = w[1];
    h->status = w[2];
    h->nsamples = w[3];
    h->trig_pos = w[4];
    h->overflow = w[5];
    h->drop = w[6];
    h->post_cfg = w[7] & 0xFFFFu;
    h->source = h->status & 3u;
    h->channel = (h->status >> 2) & 7u;
    h->edge = (h->status >> 5) & 3u;
    h->triggered = (h->status >> 8) & 1u;
    h->aborted = (h->status >> 10) & 1u;
    h->immediate = (h->status >> 11) & 1u;
    if (h->magic != LAT3_MAGIC)
        return -1;
    if (h->version != LAT3_VERSION)
        return -2;
    return 0;
}

static uint8_t sample_at(uint64_t idx, int source)
{
    if (source == SRC_WALKING)
        return (uint8_t)(1u << (idx & 7u));
    return (uint8_t)idx;
}

static uint32_t pack_word(uint8_t s0, uint8_t s1, uint8_t s2, uint8_t s3)
{
    return (uint32_t)s0 | ((uint32_t)s1 << 8) | ((uint32_t)s2 << 16) |
           ((uint32_t)s3 << 24);
}

static uint32_t expected_word_n(uint64_t sample_base, uint32_t nsamples, int source)
{
    uint8_t s[4];
    int i;
    for (i = 0; i < 4; i++) {
        uint64_t idx = sample_base + (uint64_t)i;
        s[i] = (idx < nsamples) ? sample_at(idx, source) : 0;
    }
    return pack_word(s[0], s[1], s[2], s[3]);
}

static void unpack_word(uint32_t w, uint8_t *s0, uint8_t *s1, uint8_t *s2,
                        uint8_t *s3)
{
    *s0 = (uint8_t)w;
    *s1 = (uint8_t)(w >> 8);
    *s2 = (uint8_t)(w >> 16);
    *s3 = (uint8_t)(w >> 24);
}

static void verify_packed_n(const uint32_t *got, size_t nwords, uint32_t nsamples,
                            int source, verify_stats *st)
{
    size_t i;
    for (i = 0; i < nwords; i++) {
        uint32_t exp = expected_word_n((uint64_t)i * 4ull, nsamples, source);
        if (got[i] == exp) {
            st->words_ok++;
        } else {
            if (st->words_bad == 0) {
                st->first_bad_index = i;
                st->first_bad_got = got[i];
                st->first_bad_exp = exp;
            }
            st->words_bad++;
        }
    }
}

static int run_self_test(void)
{
    uint32_t buf[16];
    uint32_t hdr[8];
    verify_stats st;
    lat3_header h;
    int i;
    int rc = 0;
    uint8_t a, b, c, d;
    uint32_t cmd;

    cmd = make_cmd(CMD_START, 0, 3, EDGE_FALL, 64);
    if (((cmd >> 16) & 0xFFFFu) != 64u || (cmd & 0xFu) != CMD_START ||
        ((cmd >> 6) & 7u) != 3u || ((cmd >> 9) & 3u) != EDGE_FALL) {
        fprintf(stderr, "self-test: command packing is wrong (got 0x%08x)\n", cmd);
        rc = 1;
    }
    if (make_cmd(CMD_STOP, 0, 0, 0, 0) != CMD_STOP) {
        fprintf(stderr, "self-test: STOP command packing is wrong\n");
        rc = 1;
    }

    memset(hdr, 0, sizeof(hdr));
    hdr[0] = LAT3_MAGIC;
    hdr[1] = LAT3_VERSION;
    hdr[2] = (1u << 8) | (0u << 5) | (0u << 2) | 0u; /* triggered, rise, ch0, ctr */
    hdr[3] = 6;
    hdr[4] = 1;
    hdr[5] = 0;
    hdr[6] = 0;
    hdr[7] = 4;
    if (parse_header(hdr, &h) != 0 || !h.triggered || h.trig_pos != 1 ||
        h.nsamples != 6 || h.post_cfg != 4) {
        fprintf(stderr, "self-test: header parse failed\n");
        rc = 1;
    }
    hdr[0] ^= 1u;
    if (parse_header(hdr, &h) != -1) {
        fprintf(stderr, "self-test: bad MAGIC did not fail closed\n");
        rc = 1;
    }

    for (i = 0; i < 16; i++)
        buf[i] = expected_word_n((uint64_t)i * 4ull, 64, SRC_COUNTER);
    unpack_word(buf[0], &a, &b, &c, &d);
    if (a != 0 || b != 1 || c != 2 || d != 3) {
        fprintf(stderr, "self-test: counter word 0 packing is wrong\n");
        rc = 1;
    }
    memset(&st, 0, sizeof(st));
    verify_packed_n(buf, 16, 64, SRC_COUNTER, &st);
    if (st.words_ok != 16 || st.words_bad != 0) {
        fprintf(stderr, "self-test: expected clean counter match\n");
        rc = 1;
    }

    buf[0] = expected_word_n(0, 8, SRC_WALKING);
    unpack_word(buf[0], &a, &b, &c, &d);
    if (a != 0x01 || b != 0x02 || c != 0x04 || d != 0x08) {
        fprintf(stderr, "self-test: walking word 0 packing is wrong\n");
        rc = 1;
    }

    buf[0] = expected_word_n(0, 6, SRC_COUNTER);
    unpack_word(buf[0], &a, &b, &c, &d);
    buf[1] = expected_word_n(4, 6, SRC_COUNTER);
    unpack_word(buf[1], &a, &b, &c, &d);
    if (a != 4 || b != 5 || c != 0 || d != 0) {
        fprintf(stderr, "self-test: pad bytes must be zero past nsamples\n");
        rc = 1;
    }

    for (i = 0; i < 3; i++)
        buf[i] = expected_word_n((uint64_t)i * 4ull, 16, SRC_COUNTER);
    buf[2] ^= 0x00000100u;
    memset(&st, 0, sizeof(st));
    verify_packed_n(buf, 3, 16, SRC_COUNTER, &st);
    if (st.words_bad != 1 || st.first_bad_index != 2) {
        fprintf(stderr, "self-test: verifier did not fail closed (bad=%" PRIu64
                        " idx=%" PRIu64 ")\n",
                st.words_bad, st.first_bad_index);
        rc = 1;
    }

    if (rc == 0)
        printf("self-test PASS (cmd + LAT3 header + packer, matcher fails closed)\n");
    return rc;
}

#ifdef FT601_NO_D3XX

int main(int argc, char **argv)
{
    int i;
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--self-test") == 0 || strcmp(argv[i], "-t") == 0)
            return run_self_test();
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            printf("This binary was built without D3XX (FT601_NO_D3XX).\n"
                   "  %s --self-test\n"
                   "Rebuild with `make d3xx` after installing the FTDI D3XX SDK.\n",
                   argv[0]);
            return 0;
        }
    }
    fprintf(stderr,
            "No D3XX in this build. Run `%s --self-test` or `make d3xx`.\n",
            argv[0]);
    return 2;
}

#else /* hardware path */

static double monotonic_sec(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static unsigned parse_edge(const char *s)
{
    if (strcmp(s, "rise") == 0 || strcmp(s, "rising") == 0)
        return EDGE_RISE;
    if (strcmp(s, "fall") == 0 || strcmp(s, "falling") == 0)
        return EDGE_FALL;
    if (strcmp(s, "both") == 0)
        return EDGE_BOTH;
    if (strcmp(s, "imm") == 0 || strcmp(s, "immediate") == 0)
        return EDGE_IMM;
    return 99u;
}

static int write_word(FT_HANDLE handle, uint32_t word)
{
    ULONG xferred = 0;
    FT_STATUS st = FT_WritePipe(handle, PIPE_OUT, (PUCHAR)&word, WORD_SIZE,
                                &xferred, NULL);
    if (st != FT_OK || xferred != WORD_SIZE) {
        fprintf(stderr, "error: FT_WritePipe %lu\n", (unsigned long)st);
        return -1;
    }
    return 0;
}

static int read_exact(FT_HANDLE handle, void *buf, size_t nbytes, ULONG timeout_unused)
{
    ULONG xferred = 0;
    FT_STATUS st;
    (void)timeout_unused;
    st = FT_ReadPipe(handle, PIPE_IN, (PUCHAR)buf, (ULONG)nbytes, &xferred, NULL);
    if (st != FT_OK) {
        fprintf(stderr, "error: FT_ReadPipe %lu\n", (unsigned long)st);
        return -1;
    }
    if (xferred != nbytes) {
        fprintf(stderr, "error: short read %lu of %zu bytes\n",
                (unsigned long)xferred, nbytes);
        return -1;
    }
    return 0;
}

static void usage(const char *argv0)
{
    fprintf(stderr,
            "Usage: %s [options]\n"
            "  --index N         D3XX device index (default 0)\n"
            "  --timeout-ms N    pipe timeout (default 5000)\n"
            "  --dump FILE       write packed little-endian payload words\n"
            "  --pattern NAME    counter|walking|none (default counter)\n"
            "  --source N        0=counter 1=walking 2=live\n"
            "  --channel N       trigger channel 0-7 (default 0)\n"
            "  --edge NAME       rise|fall|both|imm (default rise)\n"
            "  --post N          post-trigger samples (default FPGA default)\n"
            "  --stop            send STOP instead of START (dump whatever is armed)\n"
            "  --self-test       no hardware; test the packer/header/matcher\n"
            "  --help\n",
            argv0);
}

int main(int argc, char **argv)
{
    ULONG index = 0;
    ULONG timeout_ms = 5000;
    const char *dump_path = NULL;
    const char *pattern = "counter";
    int source_val = 0;
    unsigned channel = 0;
    unsigned edge = EDGE_RISE;
    unsigned post_n = 0;
    int send_stop = 0;
    int i;
    FT_HANDLE handle = NULL;
    FT_STATUS st;
    uint32_t hdr_raw[HDR_WORDS];
    lat3_header hdr;
    uint32_t *rx = NULL;
    size_t nwords;
    verify_stats vs;
    FILE *dump = NULL;
    double t0, t1;
    int check_pattern = 1;
    int src_id = SRC_COUNTER;

    for (i = 1; i < argc; i++) {
        if ((strcmp(argv[i], "--index") == 0) && i + 1 < argc) {
            index = (ULONG)strtoul(argv[++i], NULL, 0);
        } else if ((strcmp(argv[i], "--timeout-ms") == 0) && i + 1 < argc) {
            timeout_ms = (ULONG)strtoul(argv[++i], NULL, 0);
        } else if ((strcmp(argv[i], "--dump") == 0) && i + 1 < argc) {
            dump_path = argv[++i];
        } else if ((strcmp(argv[i], "--pattern") == 0) && i + 1 < argc) {
            pattern = argv[++i];
        } else if ((strcmp(argv[i], "--source") == 0) && i + 1 < argc) {
            source_val = (int)strtol(argv[++i], NULL, 0);
        } else if ((strcmp(argv[i], "--channel") == 0) && i + 1 < argc) {
            channel = (unsigned)strtoul(argv[++i], NULL, 0);
        } else if ((strcmp(argv[i], "--edge") == 0) && i + 1 < argc) {
            edge = parse_edge(argv[++i]);
        } else if ((strcmp(argv[i], "--post") == 0) && i + 1 < argc) {
            post_n = (unsigned)strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "--stop") == 0) {
            send_stop = 1;
        } else if (strcmp(argv[i], "--self-test") == 0 ||
                   strcmp(argv[i], "-t") == 0) {
            return run_self_test();
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage(argv[0]);
            return 0;
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    if (edge > EDGE_IMM) {
        fprintf(stderr, "error: --edge must be rise|fall|both|imm\n");
        return 2;
    }
    if (channel > 7u) {
        fprintf(stderr, "error: --channel must be 0-7\n");
        return 2;
    }
    if (strcmp(pattern, "none") == 0) {
        check_pattern = 0;
    } else if (strcmp(pattern, "walking") == 0) {
        src_id = SRC_WALKING;
    } else if (strcmp(pattern, "counter") != 0) {
        fprintf(stderr, "error: --pattern must be counter|walking|none\n");
        return 2;
    }

    if (dump_path) {
        dump = fopen(dump_path, "wb");
        if (!dump) {
            fprintf(stderr, "error: cannot open dump file\n");
            return 1;
        }
    }

    st = FT_Create((PVOID)(uintptr_t)index, FT_OPEN_BY_INDEX, &handle);
    if (st != FT_OK || handle == NULL) {
        fprintf(stderr, "error: FT_Create index %lu failed (%lu)\n",
                (unsigned long)index, (unsigned long)st);
        if (dump)
            fclose(dump);
        return 1;
    }

    FT_SetPipeTimeout(handle, PIPE_OUT, timeout_ms);
    FT_SetPipeTimeout(handle, PIPE_IN, timeout_ms);

    memset(&vs, 0, sizeof(vs));
    t0 = monotonic_sec();

    {
        uint32_t cmd = send_stop
                           ? make_cmd(CMD_STOP, (unsigned)source_val, channel, edge,
                                      post_n)
                           : make_cmd(CMD_START, (unsigned)source_val, channel, edge,
                                      post_n);
        if (write_word(handle, cmd) != 0) {
            FT_Close(handle);
            if (dump)
                fclose(dump);
            return 1;
        }
    }

    if (read_exact(handle, hdr_raw, HDR_BYTES, timeout_ms) != 0) {
        FT_Close(handle);
        if (dump)
            fclose(dump);
        return 1;
    }
    if (parse_header(hdr_raw, &hdr) != 0) {
        fprintf(stderr, "error: LAT3 header magic/version mismatch (got 0x%08x 0x%08x)\n",
                hdr_raw[0], hdr_raw[1]);
        FT_Close(handle);
        if (dump)
            fclose(dump);
        return 1;
    }

    nwords = ((size_t)hdr.nsamples + 3u) / 4u;
    printf("t=0.000000s  header  magic=LAT3  nsamp=%u  tpos=%s%u  ovf=%u  drop=%u\n",
           hdr.nsamples, hdr.triggered ? "" : "none/",
           hdr.triggered ? hdr.trig_pos : 0u, hdr.overflow, hdr.drop);

    rx = (uint32_t *)malloc(nwords ? nwords * WORD_SIZE : WORD_SIZE);
    if (!rx) {
        fprintf(stderr, "error: out of memory\n");
        FT_Close(handle);
        if (dump)
            fclose(dump);
        return 1;
    }

    if (nwords) {
        size_t nbytes = nwords * WORD_SIZE;
        uint8_t a, b, c, d;
        double now;
        if (read_exact(handle, rx, nbytes, timeout_ms) != 0) {
            free(rx);
            FT_Close(handle);
            if (dump)
                fclose(dump);
            return 1;
        }
        now = monotonic_sec();
        unpack_word(rx[0], &a, &b, &c, &d);
        printf("t=%.6fs  payload  bytes=%zu  samples=%u  first=%02x %02x %02x %02x\n",
               now - t0, nbytes, hdr.nsamples, a, b, c, d);
        if (dump)
            fwrite(rx, 1, nbytes, dump);
        if (check_pattern)
            verify_packed_n(rx, nwords, hdr.nsamples, src_id, &vs);
    }

    t1 = monotonic_sec();
    FT_Close(handle);
    if (dump)
        fclose(dump);
    free(rx);

    {
        double dt = t1 - t0;
        printf("mode        : triggered capture\n");
        printf("triggered   : %s\n", hdr.triggered ? "yes" : "no");
        printf("trig_pos    : %u\n", hdr.triggered ? hdr.trig_pos : 0xffffffffu);
        printf("nsamples    : %u\n", hdr.nsamples);
        printf("overflow    : %u\n", hdr.overflow);
        printf("drop        : %u\n", hdr.drop);
        printf("post_cfg    : %u\n", hdr.post_cfg);
        printf("channel     : %u\n", hdr.channel);
        printf("edge        : %u\n", hdr.edge);
        printf("seconds     : %.4f\n", dt);
        if (dump_path)
            printf("dump        : %s\n", dump_path);
        if (check_pattern) {
            printf("pattern     : %s\n", pattern);
            printf("words_ok    : %" PRIu64 "\n", vs.words_ok);
            printf("words_bad   : %" PRIu64 "\n", vs.words_bad);
            if (vs.words_bad) {
                printf("first_bad   : word=%" PRIu64 " got=0x%08x exp=0x%08x\n",
                       vs.first_bad_index, vs.first_bad_got, vs.first_bad_exp);
            }
        }
    }

    if (check_pattern) {
        if (vs.words_bad != 0 || vs.bytes_odd != 0) {
            fprintf(stderr, "FAIL: packed-sample mismatch\n");
            return 1;
        }
        printf("PASS\n");
        return 0;
    }
    printf("PASS (dump only, pattern not checked)\n");
    return 0;
}

#endif
