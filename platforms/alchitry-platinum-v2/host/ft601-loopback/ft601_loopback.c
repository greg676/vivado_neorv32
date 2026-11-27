/*
 * FT601 32-bit loopback / TX-counter host tool (FTDI D3XX).
 *
 * Default: send an incrementing 32-bit counter, read it back, fail closed on
 * dropped words, bit swaps, or short/odd transfers. Prints sustained MB/s.
 *
 * Build:
 *   make              -> pattern self-test (no SDK)
 *   make d3xx         -> hardware tool (needs D3XX SDK; see README.md)
 */

#include <errno.h>
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
            "  --bytes N       bytes to transfer (default 16777216)\n"
            "  --index N       D3XX device index (default 0)\n"
            "  --tx-only       read-only; expect FPGA TX_COUNTER bitstream\n"
            "  --timeout-ms N  pipe timeout (default 5000)\n"
            "  --self-test     no hardware; test the matcher\n"
            "  --help\n",
            argv0);
}

int main(int argc, char **argv)
{
    uint64_t nbytes = 16u * 1024u * 1024u;
    ULONG index = 0;
    ULONG timeout_ms = 5000;
    int tx_only = 0;
    int i;
    FT_HANDLE handle = NULL;
    FT_STATUS st;
    uint32_t *tx = NULL;
    uint32_t *rx = NULL;
    size_t nwords;
    size_t chunk_words = 16u * 1024u;
    verify_stats vs;
    uint64_t next_idx = 0;
    uint64_t bytes_done = 0;
    double t0, t1;

    for (i = 1; i < argc; i++) {
        if ((strcmp(argv[i], "--bytes") == 0) && i + 1 < argc) {
            nbytes = strtoull(argv[++i], NULL, 0);
        } else if ((strcmp(argv[i], "--index") == 0) && i + 1 < argc) {
            index = (ULONG)strtoul(argv[++i], NULL, 0);
        } else if ((strcmp(argv[i], "--timeout-ms") == 0) && i + 1 < argc) {
            timeout_ms = (ULONG)strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "--tx-only") == 0) {
            tx_only = 1;
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
    nwords = (size_t)(nbytes / WORD_SIZE);
    if (chunk_words > nwords)
        chunk_words = nwords;

    tx = (uint32_t *)malloc(chunk_words * WORD_SIZE);
    rx = (uint32_t *)malloc(chunk_words * WORD_SIZE);
    if (!tx || !rx) {
        fprintf(stderr, "error: out of memory\n");
        return 1;
    }

    st = FT_Create((PVOID)(uintptr_t)index, FT_OPEN_BY_INDEX, &handle);
    if (st != FT_OK || handle == NULL) {
        fprintf(stderr, "error: FT_Create index %lu failed (%lu)\n",
                (unsigned long)index, (unsigned long)st);
        free(tx);
        free(rx);
        return 1;
    }

    FT_SetPipeTimeout(handle, PIPE_OUT, timeout_ms);
    FT_SetPipeTimeout(handle, PIPE_IN, timeout_ms);

    memset(&vs, 0, sizeof(vs));
    t0 = monotonic_sec();

    while (bytes_done < nbytes) {
        size_t this_words = chunk_words;
        size_t remaining = (size_t)((nbytes - bytes_done) / WORD_SIZE);
        ULONG xferred = 0;
        size_t w;

        if (this_words > remaining)
            this_words = remaining;

        if (!tx_only) {
            for (w = 0; w < this_words; w++)
                tx[w] = pattern_word(next_idx + w);
            xferred = 0;
            st = FT_WritePipe(handle, PIPE_OUT, (PUCHAR)tx,
                              (ULONG)(this_words * WORD_SIZE), &xferred, NULL);
            if (st != FT_OK || xferred != this_words * WORD_SIZE) {
                fprintf(stderr,
                        "error: FT_WritePipe %lu (%lu bytes of %zu)\n",
                        (unsigned long)st, (unsigned long)xferred,
                        this_words * WORD_SIZE);
                vs.bytes_odd += (this_words * WORD_SIZE) - xferred;
                break;
            }
            if ((xferred % WORD_SIZE) != 0)
                vs.bytes_odd += xferred % WORD_SIZE;
        }

        xferred = 0;
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
            /* still verify whatever arrived, then fail closed */
        }

        {
            size_t got_words = (size_t)xferred / WORD_SIZE;
            verify_words(rx, got_words, next_idx, &vs);
            if (got_words != this_words)
                vs.words_bad += (this_words - got_words);
            next_idx += this_words;
            bytes_done += this_words * WORD_SIZE;
        }
    }

    t1 = monotonic_sec();
    FT_Close(handle);
    free(tx);
    free(rx);

    {
        double dt = t1 - t0;
        double mibps = (dt > 0.0) ? ((double)bytes_done / (1024.0 * 1024.0)) / dt : 0.0;
        printf("mode        : %s\n", tx_only ? "tx-only" : "loopback");
        printf("bytes       : %" PRIu64 "\n", bytes_done);
        printf("seconds     : %.4f\n", dt);
        printf("throughput  : %.2f MiB/s\n", mibps);
        printf("words_ok    : %" PRIu64 "\n", vs.words_ok);
        printf("words_bad   : %" PRIu64 "\n", vs.words_bad);
        printf("odd_bytes   : %" PRIu64 "\n", vs.bytes_odd);
        if (vs.words_bad) {
            printf("first_bad   : idx=%" PRIu64 " got=0x%08x exp=0x%08x\n",
                   vs.first_bad_index, vs.first_bad_got, vs.first_bad_exp);
        }
    }

    if (vs.words_bad != 0 || vs.bytes_odd != 0 || bytes_done != nbytes) {
        fprintf(stderr, "FAIL: loopback mismatch or incomplete transfer\n");
        return 1;
    }
    printf("PASS\n");
    return 0;
}

#endif
