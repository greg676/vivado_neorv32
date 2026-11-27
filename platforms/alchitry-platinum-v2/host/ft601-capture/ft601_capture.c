/*
 * FT601 LA capture dump (FTDI D3XX).
 *
 * Reads packed 8-bit samples (little-endian 32-bit words) from the dedicated
 * LA capture bitstream. Prints timestamped blocks; optional file dump and
 * on-FPGA pattern check.
 *
 * Build:
 *   make              -> packer self-test (no SDK)
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

#define SRC_COUNTER 0
#define SRC_WALKING 1

typedef struct {
    uint64_t words_ok;
    uint64_t words_bad;
    uint64_t first_bad_index;
    uint32_t first_bad_got;
    uint32_t first_bad_exp;
    uint64_t bytes_odd;
} verify_stats;

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

static uint32_t expected_word(uint64_t word_idx, int source)
{
    uint64_t base = word_idx * 4ull;
    return pack_word(sample_at(base, source), sample_at(base + 1, source),
                     sample_at(base + 2, source), sample_at(base + 3, source));
}

static void unpack_word(uint32_t w, uint8_t *s0, uint8_t *s1, uint8_t *s2,
                        uint8_t *s3)
{
    *s0 = (uint8_t)w;
    *s1 = (uint8_t)(w >> 8);
    *s2 = (uint8_t)(w >> 16);
    *s3 = (uint8_t)(w >> 24);
}

static void verify_packed(const uint32_t *got, size_t nwords,
                          uint64_t start_word, int source, verify_stats *st)
{
    size_t i;
    for (i = 0; i < nwords; i++) {
        uint32_t exp = expected_word(start_word + i, source);
        if (got[i] == exp) {
            st->words_ok++;
        } else {
            if (st->words_bad == 0) {
                st->first_bad_index = start_word + i;
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
    verify_stats st;
    int i;
    int rc = 0;
    uint8_t a, b, c, d;

    for (i = 0; i < 16; i++)
        buf[i] = expected_word((uint64_t)i, SRC_COUNTER);
    unpack_word(buf[0], &a, &b, &c, &d);
    if (a != 0 || b != 1 || c != 2 || d != 3) {
        fprintf(stderr, "self-test: counter word 0 packing is wrong\n");
        rc = 1;
    }
    memset(&st, 0, sizeof(st));
    verify_packed(buf, 16, 0, SRC_COUNTER, &st);
    if (st.words_ok != 16 || st.words_bad != 0) {
        fprintf(stderr, "self-test: expected clean counter match\n");
        rc = 1;
    }

    buf[0] = expected_word(0, SRC_WALKING);
    buf[1] = expected_word(1, SRC_WALKING);
    unpack_word(buf[0], &a, &b, &c, &d);
    if (a != 0x01 || b != 0x02 || c != 0x04 || d != 0x08) {
        fprintf(stderr, "self-test: walking word 0 packing is wrong\n");
        rc = 1;
    }
    unpack_word(buf[1], &a, &b, &c, &d);
    if (a != 0x10 || b != 0x20 || c != 0x40 || d != 0x80) {
        fprintf(stderr, "self-test: walking word 1 packing is wrong\n");
        rc = 1;
    }

    for (i = 0; i < 3; i++)
        buf[i] = expected_word((uint64_t)i, SRC_COUNTER);
    buf[2] ^= 0x00000100u;
    memset(&st, 0, sizeof(st));
    verify_packed(buf, 3, 0, SRC_COUNTER, &st);
    if (st.words_bad != 1 || st.first_bad_index != 2) {
        fprintf(stderr, "self-test: verifier did not fail closed (bad=%" PRIu64
                        " idx=%" PRIu64 ")\n",
                st.words_bad, st.first_bad_index);
        rc = 1;
    }

    if (rc == 0)
        printf("self-test PASS (packer round-trip + matcher fails closed)\n");
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

static void usage(const char *argv0)
{
    fprintf(stderr,
            "Usage: %s [options]\n"
            "  --bytes N         bytes to read (default 16777216)\n"
            "  --index N         D3XX device index (default 0)\n"
            "  --timeout-ms N    pipe timeout (default 5000)\n"
            "  --dump FILE       write packed little-endian words\n"
            "  --pattern NAME    counter|walking|none (default counter)\n"
            "  --source N        write 0=counter 1=walking 2=live before dump\n"
            "  --self-test       no hardware; test the packer/matcher\n"
            "  --help\n",
            argv0);
}

int main(int argc, char **argv)
{
    uint64_t nbytes = 16u * 1024u * 1024u;
    ULONG index = 0;
    ULONG timeout_ms = 5000;
    const char *dump_path = NULL;
    const char *pattern = "counter";
    int source_set = 0;
    int source_val = 0;
    int i;
    FT_HANDLE handle = NULL;
    FT_STATUS st;
    uint32_t *rx = NULL;
    size_t nwords;
    size_t chunk_words = 16u * 1024u;
    verify_stats vs;
    uint64_t next_word = 0;
    uint64_t bytes_done = 0;
    uint64_t block = 0;
    FILE *dump = NULL;
    double t0, t1;
    int check_pattern = 1;
    int src_id = SRC_COUNTER;

    for (i = 1; i < argc; i++) {
        if ((strcmp(argv[i], "--bytes") == 0) && i + 1 < argc) {
            nbytes = strtoull(argv[++i], NULL, 0);
        } else if ((strcmp(argv[i], "--index") == 0) && i + 1 < argc) {
            index = (ULONG)strtoul(argv[++i], NULL, 0);
        } else if ((strcmp(argv[i], "--timeout-ms") == 0) && i + 1 < argc) {
            timeout_ms = (ULONG)strtoul(argv[++i], NULL, 0);
        } else if ((strcmp(argv[i], "--dump") == 0) && i + 1 < argc) {
            dump_path = argv[++i];
        } else if ((strcmp(argv[i], "--pattern") == 0) && i + 1 < argc) {
            pattern = argv[++i];
        } else if ((strcmp(argv[i], "--source") == 0) && i + 1 < argc) {
            source_set = 1;
            source_val = (int)strtol(argv[++i], NULL, 0);
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

    if (nbytes < WORD_SIZE || (nbytes % WORD_SIZE) != 0) {
        fprintf(stderr, "error: --bytes must be a positive multiple of 4\n");
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

    nwords = (size_t)(nbytes / WORD_SIZE);
    if (chunk_words > nwords)
        chunk_words = nwords;

    rx = (uint32_t *)malloc(chunk_words * WORD_SIZE);
    if (!rx) {
        fprintf(stderr, "error: out of memory\n");
        return 1;
    }
    if (dump_path) {
        dump = fopen(dump_path, "wb");
        if (!dump) {
            fprintf(stderr, "error: cannot open dump file\n");
            free(rx);
            return 1;
        }
    }

    st = FT_Create((PVOID)(uintptr_t)index, FT_OPEN_BY_INDEX, &handle);
    if (st != FT_OK || handle == NULL) {
        fprintf(stderr, "error: FT_Create index %lu failed (%lu)\n",
                (unsigned long)index, (unsigned long)st);
        if (dump)
            fclose(dump);
        free(rx);
        return 1;
    }

    FT_SetPipeTimeout(handle, PIPE_OUT, timeout_ms);
    FT_SetPipeTimeout(handle, PIPE_IN, timeout_ms);

    memset(&vs, 0, sizeof(vs));
    t0 = monotonic_sec();

    if (source_set) {
        uint32_t cmd = (uint32_t)source_val;
        ULONG xferred = 0;
        st = FT_WritePipe(handle, PIPE_OUT, (PUCHAR)&cmd, WORD_SIZE, &xferred,
                          NULL);
        if (st != FT_OK || xferred != WORD_SIZE) {
            fprintf(stderr, "error: FT_WritePipe source select %lu\n",
                    (unsigned long)st);
            FT_Close(handle);
            if (dump)
                fclose(dump);
            free(rx);
            return 1;
        }
    }

    while (bytes_done < nbytes) {
        size_t this_words = chunk_words;
        size_t remaining = (size_t)((nbytes - bytes_done) / WORD_SIZE);
        ULONG xferred = 0;
        uint8_t a, b, c, d;
        double now;

        if (this_words > remaining)
            this_words = remaining;

        st = FT_ReadPipe(handle, PIPE_IN, (PUCHAR)rx,
                         (ULONG)(this_words * WORD_SIZE), &xferred, NULL);
        if (st != FT_OK) {
            fprintf(stderr, "error: FT_ReadPipe %lu\n", (unsigned long)st);
            break;
        }
        if ((xferred % WORD_SIZE) != 0) {
            fprintf(stderr, "error: odd read %lu bytes (not a whole word)\n",
                    (unsigned long)xferred);
            vs.bytes_odd += xferred % WORD_SIZE;
            break;
        }
        if (xferred != this_words * WORD_SIZE) {
            fprintf(stderr, "error: short read %lu of %zu bytes\n",
                    (unsigned long)xferred, this_words * WORD_SIZE);
            vs.bytes_odd += (this_words * WORD_SIZE) - xferred;
        }

        {
            size_t got_words = (size_t)xferred / WORD_SIZE;
            now = monotonic_sec();
            if (got_words > 0) {
                unpack_word(rx[0], &a, &b, &c, &d);
                printf("t=%.6fs  block=%" PRIu64 "  bytes=%lu  samples=%lu  "
                       "first=%02x %02x %02x %02x\n",
                       now - t0, block, (unsigned long)xferred,
                       (unsigned long)xferred, a, b, c, d);
            } else {
                printf("t=%.6fs  block=%" PRIu64 "  bytes=0  samples=0\n",
                       now - t0, block);
            }
            if (dump && xferred)
                fwrite(rx, 1, xferred, dump);
            if (check_pattern)
                verify_packed(rx, got_words, next_word, src_id, &vs);
            if (got_words != this_words && check_pattern)
                vs.words_bad += (this_words - got_words);
            next_word += this_words;
            bytes_done += this_words * WORD_SIZE;
            block++;
        }
    }

    t1 = monotonic_sec();
    FT_Close(handle);
    if (dump)
        fclose(dump);
    free(rx);

    {
        double dt = t1 - t0;
        double mibps = (dt > 0.0) ? ((double)bytes_done / (1024.0 * 1024.0)) / dt
                                  : 0.0;
        printf("mode        : capture dump\n");
        printf("bytes       : %" PRIu64 "\n", bytes_done);
        printf("samples     : %" PRIu64 "\n", bytes_done);
        printf("blocks      : %" PRIu64 "\n", block);
        printf("seconds     : %.4f\n", dt);
        printf("throughput  : %.2f MiB/s\n", mibps);
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
        if (vs.words_bad != 0 || vs.bytes_odd != 0 || bytes_done != nbytes) {
            fprintf(stderr, "FAIL: packed-sample mismatch or incomplete transfer\n");
            return 1;
        }
        printf("PASS\n");
        return 0;
    }
    if (vs.bytes_odd != 0 || bytes_done != nbytes) {
        fprintf(stderr, "FAIL: incomplete transfer\n");
        return 1;
    }
    printf("PASS (dump only, pattern not checked)\n");
    return 0;
}

#endif
