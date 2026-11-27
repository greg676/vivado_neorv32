// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
/*
 * FT601 32-bit loopback / TX-counter host tool.
 *
 * Default: send an incrementing 32-bit counter, read it back, fail closed on
 * dropped words, bit swaps, or short/odd transfers. Prints sustained MB/s.
 *
 * Build:
 *   make              -> pattern self-test (no USB)
 *   make hw           -> hardware tool (libusb, default)
 *   make d3xx         -> hardware tool (FTDI D3XX SDK at /opt/ftdi/d3xx)
 */

#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifndef FT601_NO_HW
#include "ft601_usb.h"
#endif

#define WORD_SIZE 4u

typedef struct {
    uint64_t words_ok;
    uint64_t words_bad;
    uint64_t first_bad_index;
    uint32_t first_bad_got;
    uint32_t first_bad_exp;
    uint64_t bytes_odd;
} verify_stats;

static uint32_t pattern_word(uint64_t idx)
{
    return (uint32_t)idx;
}

static void verify_words(const uint32_t *got, size_t nwords, uint64_t start_idx,
                         verify_stats *st)
{
    size_t i;
    for (i = 0; i < nwords; i++) {
        uint32_t exp = pattern_word(start_idx + i);
        if (got[i] == exp) {
            st->words_ok++;
        } else {
            if (st->words_bad == 0) {
                st->first_bad_index = start_idx + i;
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

    memset(&st, 0, sizeof(st));
    for (i = 0; i < 16; i++)
        buf[i] = pattern_word((uint64_t)i);
    verify_words(buf, 16, 0, &st);
    if (st.words_ok != 16 || st.words_bad != 0) {
        fprintf(stderr, "self-test: expected clean match\n");
        rc = 1;
    }

    memset(&st, 0, sizeof(st));
    buf[3] ^= 0x00010000u; /* bit swap */
    buf[7] = 99;           /* drop / substitution */
    verify_words(buf, 16, 0, &st);
    if (st.words_bad != 2 || st.first_bad_index != 3) {
        fprintf(stderr, "self-test: verifier did not fail closed (bad=%" PRIu64
                        " idx=%" PRIu64 ")\n",
                st.words_bad, st.first_bad_index);
        rc = 1;
    }

    if (rc == 0)
        printf("self-test PASS (matcher fails closed on bit-swap and drop)\n");
    return rc;
}

#ifdef FT601_NO_HW

int main(int argc, char **argv)
{
    int i;
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--self-test") == 0 || strcmp(argv[i], "-t") == 0)
            return run_self_test();
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            printf("This binary was built without USB (FT601_NO_HW).\n"
                   "  %s --self-test\n"
                   "Rebuild with `make hw` (libusb) or `make d3xx`.\n",
                   argv[0]);
            return 0;
        }
    }
    fprintf(stderr,
            "No USB in this build. Run `%s --self-test` or `make hw`.\n",
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

static uint32_t packed_word(uint64_t sample_base)
{
    uint32_t s0 = (uint32_t)sample_base & 0xFFu;
    uint32_t s1 = (uint32_t)(sample_base + 1u) & 0xFFu;
    uint32_t s2 = (uint32_t)(sample_base + 2u) & 0xFFu;
    uint32_t s3 = (uint32_t)(sample_base + 3u) & 0xFFu;
    return s0 | (s1 << 8) | (s2 << 16) | (s3 << 24);
}

static void verify_packed(const uint32_t *got, size_t nwords, uint64_t start_sample,
                          verify_stats *st)
{
    size_t i;
    for (i = 0; i < nwords; i++) {
        uint32_t exp = packed_word(start_sample + (uint64_t)i * 4u);
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

static void usage(const char *argv0)
{
    fprintf(stderr,
            "Usage: %s [options]\n"
            "  --bytes N       bytes to transfer (default 16777216)\n"
            "  --index N       FT601 index if several 0403:601f (default 0)\n"
            "  --tx-only       read-only; expect FPGA TX_COUNTER bitstream\n"
            "  --packed-counter  read-only; expect LA packed 8-bit counter (dual-BRAM)\n"
            "  --timeout-ms N  pipe timeout (default 5000)\n"
            "  --chunk-bytes N D3XX IN URB (default 262144; 256 KiB..1 MiB with --stream)\n"
            "  --nflight N     overlapped URBs in flight (default 4; 2..8)\n"
            "  --no-stream     16 KiB one-shot FT_ReadPipeEx (old Jetson path)\n"
            "  --sink          TX-only rate; discard payload (no memcpy/verify)\n"
            "  --vector PATH   LE 32-bit .bin from sim/ft601/vectors\n"
            "  --self-test     no hardware; test the matcher\n"
            "  --help\n",
            argv0);
}

static int load_vector_file(const char *path, uint32_t **out, size_t *nwords)
{
    FILE *f = fopen(path, "rb");
    long sz;
    uint32_t *buf;
    size_t n, got;

    if (!f) {
        fprintf(stderr, "error: cannot open %s: %s\n", path, strerror(errno));
        return -1;
    }
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return -1;
    }
    sz = ftell(f);
    rewind(f);
    if (sz < (long)WORD_SIZE || (sz % (long)WORD_SIZE) != 0) {
        fprintf(stderr, "error: %s length %ld is not a multiple of 4\n", path, sz);
        fclose(f);
        return -1;
    }
    n = (size_t)sz / WORD_SIZE;
    buf = (uint32_t *)malloc((size_t)sz);
    if (!buf) {
        fclose(f);
        return -1;
    }
    got = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    if (got != (size_t)sz) {
        free(buf);
        return -1;
    }
    *out = buf;
    *nwords = n;
    return 0;
}

int main(int argc, char **argv)
{
    uint64_t nbytes = 16u * 1024u * 1024u;
    int index = 0;
    unsigned timeout_ms = 5000;
    int tx_only = 0;
    int packed_counter = 0;
    int use_stream = 1;
    int sink = 0;
    unsigned chunk_bytes = 256u * 1024u;
    unsigned nflight = 4;
    const char *vector_path = NULL;
    uint32_t *vector = NULL;
    size_t vector_n = 0;
    int i;
    ft601_dev *dev = NULL;
    char err[256];
    uint32_t *tx = NULL;
    uint32_t *rx = NULL;
    size_t nwords;
    size_t chunk_words;
    verify_stats vs;
    uint64_t next_idx = 0;
    uint64_t bytes_done = 0;
    double t0, t1;

    for (i = 1; i < argc; i++) {
        if ((strcmp(argv[i], "--bytes") == 0) && i + 1 < argc) {
            nbytes = strtoull(argv[++i], NULL, 0);
        } else if ((strcmp(argv[i], "--index") == 0) && i + 1 < argc) {
            index = (int)strtol(argv[++i], NULL, 0);
        } else if ((strcmp(argv[i], "--timeout-ms") == 0) && i + 1 < argc) {
            timeout_ms = (unsigned)strtoul(argv[++i], NULL, 0);
        } else if ((strcmp(argv[i], "--chunk-bytes") == 0) && i + 1 < argc) {
            unsigned long cb = strtoul(argv[++i], NULL, 0);
            if (cb < WORD_SIZE || (cb % WORD_SIZE) != 0) {
                fprintf(stderr, "error: --chunk-bytes must be a multiple of 4\n");
                return 2;
            }
            chunk_bytes = (unsigned)cb;
        } else if ((strcmp(argv[i], "--nflight") == 0) && i + 1 < argc) {
            nflight = (unsigned)strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "--tx-only") == 0) {
            tx_only = 1;
        } else if (strcmp(argv[i], "--packed-counter") == 0) {
            packed_counter = 1;
            tx_only = 1;
        } else if (strcmp(argv[i], "--no-stream") == 0) {
            use_stream = 0;
            chunk_bytes = 16384;
        } else if (strcmp(argv[i], "--sink") == 0) {
            sink = 1;
            tx_only = 1;
        } else if ((strcmp(argv[i], "--vector") == 0) && i + 1 < argc) {
            vector_path = argv[++i];
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
    if (vector_path) {
        if (load_vector_file(vector_path, &vector, &vector_n) != 0)
            return 2;
        printf("vector      : %s (%zu words, repeating)\n", vector_path, vector_n);
    }

    nwords = (size_t)(nbytes / WORD_SIZE);
    chunk_words = (size_t)(chunk_bytes / WORD_SIZE);
    if (chunk_words == 0)
        chunk_words = 1;
    if (chunk_words > nwords)
        chunk_words = nwords;

    /* TX-only / packed: one IN of nbytes so several URBs stay in flight. */
    if (sink) {
        tx = (uint32_t *)malloc(WORD_SIZE);
        rx = (uint32_t *)calloc(8, WORD_SIZE);
    } else if (tx_only) {
        tx = (uint32_t *)malloc(WORD_SIZE);
        rx = (uint32_t *)malloc((size_t)nbytes);
    } else {
        tx = (uint32_t *)malloc(chunk_words * WORD_SIZE);
        rx = (uint32_t *)malloc(chunk_words * WORD_SIZE);
    }
    if (!tx || !rx) {
        fprintf(stderr, "error: out of memory\n");
        return 1;
    }

    dev = ft601_open(index, timeout_ms, err, sizeof(err));
    if (!dev) {
        fprintf(stderr, "error: %s\n", err);
        free(tx);
        free(rx);
        free(vector);
        return 1;
    }
    if (use_stream && tx_only && nbytes >= chunk_bytes) {
        if (ft601_configure_in_stream(dev, chunk_bytes, nflight, err,
                                      sizeof(err)) != 0) {
            fprintf(stderr, "warning: IN stream off (%s)\n", err);
        }
    } else if (use_stream && !tx_only) {
        printf("in_stream   : skipped (echo stays 16 KiB OUT/IN)\n");
    }
    printf("FT601 backend : %s\n", ft601_backend_name());
    printf("in_path     : %s\n", ft601_in_path(dev));
    printf("chunk_bytes : %u\n", chunk_bytes);
    printf("nflight     : %u\n", nflight);

    memset(&vs, 0, sizeof(vs));
    t0 = monotonic_sec();

    if (tx_only) {
        size_t xferred = 0;
        void *dst = sink ? NULL : rx;
        if (ft601_read(dev, dst, (size_t)nbytes, &xferred) != 0) {
            fprintf(stderr, "error: read failed (%zu bytes)\n", xferred);
            vs.bytes_odd += ((size_t)nbytes > xferred) ? ((size_t)nbytes - xferred)
                                                       : 0;
        }
        if (xferred % WORD_SIZE)
            vs.bytes_odd += xferred % WORD_SIZE;
        bytes_done = xferred - (xferred % WORD_SIZE);
        if (sink) {
            vs.words_ok = bytes_done / WORD_SIZE;
        } else {
            size_t got_words = (size_t)bytes_done / WORD_SIZE;
            if (packed_counter && got_words) {
                uint64_t start_sample = (uint64_t)(rx[0] & 0xFFu);
                verify_packed(rx, got_words, start_sample, &vs);
            } else if (vector) {
                size_t gi;
                for (gi = 0; gi < got_words; gi++) {
                    uint32_t exp = vector[gi % vector_n];
                    if (rx[gi] == exp) {
                        vs.words_ok++;
                    } else {
                        if (vs.words_bad == 0) {
                            vs.first_bad_index = gi;
                            vs.first_bad_got = rx[gi];
                            vs.first_bad_exp = exp;
                        }
                        vs.words_bad++;
                    }
                }
            } else {
                /* FPGA free-runs across host opens; consecutive from first word. */
                verify_words(rx, got_words, (uint64_t)rx[0], &vs);
            }
            if (bytes_done != nbytes)
                vs.words_bad += (nwords > got_words) ? (nwords - got_words) : 0;
        }
    } else {
        while (bytes_done < nbytes) {
            size_t this_words = chunk_words;
            size_t remaining = (size_t)((nbytes - bytes_done) / WORD_SIZE);
            size_t xferred = 0;
            size_t w;

            if (this_words > remaining)
                this_words = remaining;

            for (w = 0; w < this_words; w++)
                tx[w] = vector ? vector[(next_idx + w) % vector_n]
                               : pattern_word(next_idx + w);
            xferred = 0;
            if (ft601_write(dev, tx, this_words * WORD_SIZE, &xferred) != 0 ||
                xferred != this_words * WORD_SIZE) {
                fprintf(stderr, "error: write %zu bytes of %zu\n",
                        xferred, this_words * WORD_SIZE);
                vs.bytes_odd += (this_words * WORD_SIZE) - xferred;
                break;
            }
            if ((xferred % WORD_SIZE) != 0)
                vs.bytes_odd += xferred % WORD_SIZE;

            xferred = 0;
            if (ft601_read(dev, rx, this_words * WORD_SIZE, &xferred) != 0) {
                fprintf(stderr, "error: read failed (%zu bytes)\n", xferred);
                if ((xferred % WORD_SIZE) != 0)
                    vs.bytes_odd += xferred % WORD_SIZE;
                break;
            }
            if ((xferred % WORD_SIZE) != 0) {
                fprintf(stderr, "error: odd read %zu bytes (not a whole word)\n",
                        xferred);
                vs.bytes_odd += xferred % WORD_SIZE;
                break;
            }
            if (xferred != this_words * WORD_SIZE) {
                fprintf(stderr, "error: short read %zu of %zu bytes\n",
                        xferred, this_words * WORD_SIZE);
                vs.bytes_odd += (this_words * WORD_SIZE) - xferred;
            }

            {
                size_t got_words = (size_t)xferred / WORD_SIZE;
                if (vector) {
                    size_t gi;
                    for (gi = 0; gi < got_words; gi++) {
                        uint32_t exp = vector[(next_idx + gi) % vector_n];
                        if (rx[gi] == exp) {
                            vs.words_ok++;
                        } else {
                            if (vs.words_bad == 0) {
                                vs.first_bad_index = next_idx + gi;
                                vs.first_bad_got = rx[gi];
                                vs.first_bad_exp = exp;
                            }
                            vs.words_bad++;
                        }
                    }
                } else {
                    verify_words(rx, got_words, next_idx, &vs);
                }
                if (got_words != this_words)
                    vs.words_bad += (this_words - got_words);
                next_idx += this_words;
                bytes_done += this_words * WORD_SIZE;
            }
        }
    }

    t1 = monotonic_sec();
    {
        const char *in_path = ft601_in_path(dev);
        const char *mode = packed_counter ? "packed-counter (host IN)"
                           : (sink ? "tx-only sink (no memcpy)"
                              : (tx_only ? "tx-only (host IN, no OUT)" : "loopback"));
        double dt = t1 - t0;
        double mibps = (dt > 0.0) ? ((double)bytes_done / (1024.0 * 1024.0)) / dt : 0.0;
        const double theory = 400.0 * 1000.0 * 1000.0 / (1024.0 * 1024.0);

        printf("mode        : %s\n", mode);
        if (sink) {
            printf("first_8     : (sink, discarded)\n");
        } else if (bytes_done >= 4) {
            printf("first_8     : 0x%08x 0x%08x 0x%08x 0x%08x 0x%08x 0x%08x 0x%08x 0x%08x\n",
                   rx[0],
                   bytes_done >= 8 ? rx[1] : 0,
                   bytes_done >= 12 ? rx[2] : 0,
                   bytes_done >= 16 ? rx[3] : 0,
                   bytes_done >= 20 ? rx[4] : 0,
                   bytes_done >= 24 ? rx[5] : 0,
                   bytes_done >= 28 ? rx[6] : 0,
                   bytes_done >= 32 ? rx[7] : 0);
        }
        printf("in_path     : %s\n", in_path);
        printf("bytes       : %" PRIu64 "\n", bytes_done);
        printf("seconds     : %.4f\n", dt);
        printf("throughput  : %.2f MiB/s\n", mibps);
        printf("theoretical : %.2f MiB/s (32-bit x 100 MHz)\n", theory);
        printf("vs_theory   : %.1f%%\n", theory > 0.0 ? (100.0 * mibps / theory) : 0.0);
        printf("words_ok    : %" PRIu64 "\n", vs.words_ok);
        printf("words_bad   : %" PRIu64 "\n", vs.words_bad);
        printf("odd_bytes   : %" PRIu64 "\n", vs.bytes_odd);
        if (vs.words_bad) {
            printf("first_bad   : idx=%" PRIu64 " got=0x%08x exp=0x%08x\n",
                   vs.first_bad_index, vs.first_bad_got, vs.first_bad_exp);
        }
    }
    ft601_close(dev);
    free(tx);
    free(rx);
    free(vector);

    if (bytes_done != nbytes || vs.bytes_odd != 0) {
        fprintf(stderr, "FAIL: incomplete transfer\n");
        return 1;
    }
    if (vs.words_bad != 0) {
        fprintf(stderr, "FAIL: loopback mismatch or packed-counter skip\n");
        return 1;
    }
    printf("PASS\n");
    return 0;
}

#endif
