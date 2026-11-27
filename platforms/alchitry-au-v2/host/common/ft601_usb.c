#define _POSIX_C_SOURCE 200809L
/*
 * FT601 USB transport.
 *
 * Default: libusb-1.0. FT60x Function Protocol needs both interfaces:
 *   IF0 communication  EP 0x01 bulk OUT (20-byte session list)
 *                      EP 0x81 interrupt IN (unused here)
 *   IF1 data           EP 0x02 bulk OUT / EP 0x82 bulk IN (245 ch0)
 * A 20-byte session on 0x01 must precede each data transfer on 0x02/0x82.
 * Jetson: that path wrote 4+1024+4096+8192 = 13312 bytes (rc=0).
 *
 * Optional: -DFT601_USE_D3XX. On Linux call FT_SetTransferParams then
 * FT_Create, FT_SetStreamPipe, and overlapped FT_ReadPipeAsync (fifo id 0).
 * 16 KiB one-shot IN is the old Jetson path; stream is 256 KiB..1 MiB.
 */

#include "ft601_usb.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <libusb.h>

#define FT601_VID 0x0403
#define FT601_PID 0x601f
#define PIPE_OUT  0x02
#define PIPE_IN   0x82
#define EP_SESSION 0x01
#define FIFO_CH0  0
/* Jetson: 65536-byte URB times out; first 16 KiB D3XX write after reset is OK. */
#define FT601_MAX_XFER 16384u

static void ft601_bus_reset(void)
{
    libusb_context *ctx = NULL;
    libusb_device_handle *h;

    if (libusb_init(&ctx) != 0)
        return;
    h = libusb_open_device_with_vid_pid(ctx, FT601_VID, FT601_PID);
    if (h) {
        libusb_reset_device(h);
        libusb_close(h);
    }
    libusb_exit(ctx);
    sleep(1);
}

static void set_err(char *err, size_t errlen, const char *msg)
{
    if (err && errlen)
        snprintf(err, errlen, "%s", msg);
}

#ifdef FT601_USE_D3XX

#include "ftd3xx.h"

#ifndef FT_PIPE_DIR_IN
#define FT_PIPE_DIR_IN  0
#define FT_PIPE_DIR_OUT 1
#endif

#ifndef FT_FAILED
#define FT_FAILED(st) ((st) != FT_OK)
#endif

#define D3XX_MAX_WRITE 16384u
#define D3XX_DEFAULT_CHUNK FT601_STREAM_CHUNK_MIN
#define D3XX_DEFAULT_FLIGHT 4u

struct ft601_dev {
    FT_HANDLE handle;
    unsigned timeout_ms;
    unsigned chunk_bytes;
    unsigned nflight;
    int stream_on;
    const char *in_path;
    OVERLAPPED ov[FT601_STREAM_FLIGHT_MAX];
    unsigned char *urb[FT601_STREAM_FLIGHT_MAX][2];
    int urb_sel[FT601_STREAM_FLIGHT_MAX];
    int ov_inited[FT601_STREAM_FLIGHT_MAX];
};

static unsigned urb_buffer_size(void)
{
    return FT601_STREAM_CHUNK_MAX;
}

static void d3xx_set_transfer_params(void)
{
    FT_TRANSFER_CONF conf;
    DWORD i;

    memset(&conf, 0, sizeof(conf));
    conf.wStructSize = sizeof(conf);
    /* Single-thread IN; D3XX keeps several URBs queued (FTDI streamer). */
    conf.pipe[FT_PIPE_DIR_IN].fNonThreadSafeTransfer = TRUE;
    conf.pipe[FT_PIPE_DIR_IN].bURBCount = 8;
    conf.pipe[FT_PIPE_DIR_IN].wURBBufferCount = 16;
    conf.pipe[FT_PIPE_DIR_IN].dwURBBufferSize = urb_buffer_size();
    conf.pipe[FT_PIPE_DIR_OUT].fNonThreadSafeTransfer = TRUE;
    for (i = 0; i < 4; i++)
        FT_SetTransferParams(&conf, i);
}

static void d3xx_release_urbs(ft601_dev *d)
{
    unsigned i;

    if (!d || !d->handle)
        return;
    for (i = 0; i < FT601_STREAM_FLIGHT_MAX; i++) {
        if (d->ov_inited[i]) {
            FT_ReleaseOverlapped(d->handle, &d->ov[i]);
            d->ov_inited[i] = 0;
        }
        free(d->urb[i][0]);
        free(d->urb[i][1]);
        d->urb[i][0] = NULL;
        d->urb[i][1] = NULL;
        d->urb_sel[i] = 0;
    }
}

static int d3xx_prep_urbs(ft601_dev *d, unsigned nflight, unsigned chunk,
                          char *err, size_t errlen)
{
    unsigned i;

    d3xx_release_urbs(d);
    for (i = 0; i < nflight; i++) {
        d->urb[i][0] = (unsigned char *)malloc(chunk);
        d->urb[i][1] = (unsigned char *)malloc(chunk);
        if (!d->urb[i][0] || !d->urb[i][1]) {
            set_err(err, errlen, "out of memory (IN URB buffers)");
            d3xx_release_urbs(d);
            return -1;
        }
        d->urb_sel[i] = 0;
        memset(&d->ov[i], 0, sizeof(d->ov[i]));
        if (FT_InitializeOverlapped(d->handle, &d->ov[i]) != FT_OK) {
            snprintf(err, errlen, "FT_InitializeOverlapped %u failed", i);
            d3xx_release_urbs(d);
            return -1;
        }
        d->ov_inited[i] = 1;
    }
    return 0;
}

const char *ft601_backend_name(void)
{
    return "d3xx";
}

const char *ft601_in_path(const ft601_dev *d)
{
    if (!d || !d->in_path)
        return "d3xx-oneshot";
    return d->in_path;
}

ft601_dev *ft601_open(int index, unsigned timeout_ms, char *err, size_t errlen)
{
    ft601_dev *d;
    FT_STATUS st;

    d = (ft601_dev *)calloc(1, sizeof(*d));
    if (!d) {
        set_err(err, errlen, "out of memory");
        return NULL;
    }
    d->timeout_ms = timeout_ms ? timeout_ms : 5000;
    d->chunk_bytes = D3XX_DEFAULT_CHUNK;
    d->nflight = D3XX_DEFAULT_FLIGHT;
    d->in_path = "d3xx-oneshot";
    ft601_bus_reset();
    /* Linux D3XX: params before FT_Create, matching FTDI streamer. */
    d3xx_set_transfer_params();
    st = FT_Create((PVOID)(uintptr_t)index, FT_OPEN_BY_INDEX, &d->handle);
    if (st != FT_OK || d->handle == NULL) {
        snprintf(err, errlen, "FT_Create index %d failed (%lu)", index,
                 (unsigned long)st);
        free(d);
        return NULL;
    }
    FT_SetPipeTimeout(d->handle, PIPE_OUT, d->timeout_ms);
    FT_SetPipeTimeout(d->handle, PIPE_IN, d->timeout_ms);
    return d;
}

void ft601_close(ft601_dev *d)
{
    if (!d)
        return;
    if (d->handle) {
        if (d->stream_on) {
            FT_AbortPipe(d->handle, PIPE_IN);
            FT_ClearStreamPipe(d->handle, FALSE, TRUE, 0);
            FT_ClearStreamPipe(d->handle, FALSE, FALSE, PIPE_IN);
            d->stream_on = 0;
        }
        d3xx_release_urbs(d);
        FT_Close(d->handle);
    }
    free(d);
}

int ft601_configure_in_stream(ft601_dev *d, unsigned chunk_bytes,
                              unsigned nflight, char *err, size_t errlen)
{
    FT_STATUS st;

    if (!d || !d->handle) {
        set_err(err, errlen, "device not open");
        return -1;
    }
    if (chunk_bytes < FT601_STREAM_CHUNK_MIN ||
        chunk_bytes > FT601_STREAM_CHUNK_MAX ||
        (chunk_bytes % 4u) != 0) {
        snprintf(err, errlen,
                 "IN stream chunk must be 256 KiB..1 MiB and a multiple of 4 (got %u)",
                 chunk_bytes);
        return -1;
    }
    if (nflight < 2u || nflight > FT601_STREAM_FLIGHT_MAX) {
        snprintf(err, errlen, "nflight must be 2..%u (got %u)",
                 FT601_STREAM_FLIGHT_MAX, nflight);
        return -1;
    }

    if (d->stream_on) {
        FT_ClearStreamPipe(d->handle, FALSE, TRUE, 0);
        d->stream_on = 0;
    }

    /* Infinite pipe timeout like FTDI streamer.cpp; overlapped waits on the event. */
    FT_SetPipeTimeout(d->handle, PIPE_IN, 0);
    st = FT_SetStreamPipe(d->handle, FALSE, TRUE, 0, chunk_bytes);
    if (FT_FAILED(st)) {
        snprintf(err, errlen, "FT_SetStreamPipe %lu", (unsigned long)st);
        FT_SetPipeTimeout(d->handle, PIPE_IN, d->timeout_ms);
        return -1;
    }
    d->stream_on = 1;
    d->chunk_bytes = chunk_bytes;
    d->nflight = nflight;
    d->in_path = "d3xx-stream";

    if (d3xx_prep_urbs(d, nflight, chunk_bytes, err, errlen) != 0) {
        /* Stream is still useful with blocking FT_ReadPipeEx. */
        return 0;
    }
    d->in_path = "d3xx-overlapped";
    return 0;
}

int ft601_write(ft601_dev *d, const void *buf, size_t n, size_t *xferred)
{
    const unsigned char *p = (const unsigned char *)buf;
    size_t done = 0;

    if (xferred)
        *xferred = 0;
    while (done < n) {
        ULONG got = 0;
        ULONG want = (ULONG)((n - done) > D3XX_MAX_WRITE ? D3XX_MAX_WRITE
                                                         : (n - done));
        FT_STATUS st = FT_WritePipeEx(d->handle, FIFO_CH0, (PUCHAR)(p + done),
                                      want, &got, d->timeout_ms);
        done += (size_t)got;
        if (st != FT_OK || got != want) {
            if (xferred)
                *xferred = done;
            return -1;
        }
    }
    if (xferred)
        *xferred = done;
    return 0;
}

static int d3xx_read_oneshot(ft601_dev *d, unsigned char *p, size_t n,
                             size_t *xferred)
{
    size_t done = 0;
    unsigned cap = d->stream_on ? d->chunk_bytes : D3XX_MAX_WRITE;
    unsigned char *scratch = NULL;

    if (!p) {
        scratch = (unsigned char *)malloc(cap);
        if (!scratch) {
            if (xferred)
                *xferred = 0;
            return -1;
        }
    }

    while (done < n) {
        ULONG got = 0;
        ULONG want = (ULONG)((n - done) > cap ? cap : (n - done));
        unsigned char *dst = p ? (p + done) : scratch;
        FT_STATUS st = FT_ReadPipeEx(d->handle, FIFO_CH0, dst, want, &got,
                                     d->stream_on ? 0u : d->timeout_ms);
        done += (size_t)got;
        if (st != FT_OK || got != want) {
            if (xferred)
                *xferred = done;
            free(scratch);
            return -1;
        }
    }
    if (xferred)
        *xferred = done;
    free(scratch);
    return 0;
}

static int d3xx_start_async(ft601_dev *d, unsigned slot, ULONG len)
{
    ULONG dummy = 0;
    unsigned sel = (unsigned)d->urb_sel[slot] & 1u;
    FT_STATUS st = FT_ReadPipeAsync(d->handle, FIFO_CH0, d->urb[slot][sel],
                                    len, &dummy, &d->ov[slot]);
    return (st == FT_OK || st == FT_IO_PENDING) ? 0 : -1;
}

static int d3xx_read_overlapped(ft601_dev *d, unsigned char *p, size_t n,
                                size_t *xferred)
{
    unsigned nflight = d->nflight;
    unsigned chunk = d->chunk_bytes;
    size_t submitted = 0;
    size_t completed = 0;
    unsigned slot = 0;
    unsigned i;
    int active[FT601_STREAM_FLIGHT_MAX];

    if (!d->ov_inited[0] || nflight < 2u || chunk == 0)
        return d3xx_read_oneshot(d, p, n, xferred);

    memset(active, 0, sizeof(active));
    for (i = 0; i < nflight && submitted + chunk <= n; i++) {
        if (d3xx_start_async(d, i, chunk) != 0) {
            d->in_path = "d3xx-stream";
            FT_AbortPipe(d->handle, PIPE_IN);
            return d3xx_read_oneshot(d, p, n, xferred);
        }
        active[i] = 1;
        submitted += chunk;
    }
    if (submitted == 0)
        return d3xx_read_oneshot(d, p, n, xferred);

    while (completed < submitted) {
        ULONG got = 0;
        FT_STATUS st;
        unsigned spins = 0;

        while (!active[slot] && spins < nflight) {
            slot++;
            if (slot >= nflight)
                slot = 0;
            spins++;
        }
        if (!active[slot]) {
            if (xferred)
                *xferred = completed;
            FT_AbortPipe(d->handle, PIPE_IN);
            return -1;
        }

        st = FT_GetOverlappedResult(d->handle, &d->ov[slot], &got, TRUE);
        active[slot] = 0;
        if (st != FT_OK || got != chunk) {
            if (got && p)
                memcpy(p + completed, d->urb[slot][d->urb_sel[slot] & 1], got);
            completed += got;
            if (xferred)
                *xferred = completed;
            FT_AbortPipe(d->handle, PIPE_IN);
            return -1;
        }
        {
            unsigned done_sel = (unsigned)d->urb_sel[slot] & 1u;
            /* Re-queue on the other buffer before memcpy so USB stays full. */
            if (submitted + chunk <= n) {
                d->urb_sel[slot] = (int)(done_sel ^ 1u);
                if (d3xx_start_async(d, slot, chunk) != 0) {
                    if (p)
                        memcpy(p + completed, d->urb[slot][done_sel], got);
                    completed += got;
                    if (xferred)
                        *xferred = completed;
                    FT_AbortPipe(d->handle, PIPE_IN);
                    return -1;
                }
                active[slot] = 1;
                submitted += chunk;
            }
            if (p)
                memcpy(p + completed, d->urb[slot][done_sel], got);
            completed += got;
        }
        slot++;
        if (slot >= nflight)
            slot = 0;
    }

    if (completed < n) {
        size_t tail = 0;
        /* Remainder is smaller than FT_SetStreamPipe; drop the session. */
        FT_ClearStreamPipe(d->handle, FALSE, TRUE, 0);
        d->stream_on = 0;
        FT_SetPipeTimeout(d->handle, PIPE_IN, d->timeout_ms);
        if (d3xx_read_oneshot(d, p + completed, n - completed, &tail) != 0) {
            if (xferred)
                *xferred = completed + tail;
            return -1;
        }
        completed += tail;
    }
    if (xferred)
        *xferred = completed;
    return 0;
}

int ft601_read(ft601_dev *d, void *buf, size_t n, size_t *xferred)
{
    unsigned char *p = (unsigned char *)buf;

    if (xferred)
        *xferred = 0;
    if (d->stream_on)
        return d3xx_read_overlapped(d, p, n, xferred);
    return d3xx_read_oneshot(d, p, n, xferred);
}

#else /* libusb */

struct ft601_dev {
    libusb_context *ctx;
    libusb_device_handle *handle;
    unsigned char ep_out;
    unsigned char ep_in;
    int claimed0;
    int claimed1;
    uint32_t sess;
    unsigned timeout_ms;
};

const char *ft601_backend_name(void)
{
    return "libusb";
}

const char *ft601_in_path(const ft601_dev *d)
{
    (void)d;
    return "libusb-oneshot";
}

int ft601_configure_in_stream(ft601_dev *d, unsigned chunk_bytes,
                              unsigned nflight, char *err, size_t errlen)
{
    (void)d;
    (void)chunk_bytes;
    (void)nflight;
    set_err(err, errlen,
            "IN stream needs D3XX (make d3xx); libusb stays 16 KiB session URBs");
    return -1;
}

static int session_list(ft601_dev *d, unsigned char pipe, uint32_t length)
{
    unsigned char pkt[20];
    int got = 0;
    int rc;

    memset(pkt, 0, sizeof(pkt));
    d->sess++;
    pkt[0] = (unsigned char)(d->sess);
    pkt[1] = (unsigned char)(d->sess >> 8);
    pkt[2] = (unsigned char)(d->sess >> 16);
    pkt[3] = (unsigned char)(d->sess >> 24);
    pkt[4] = pipe;
    pkt[8] = (unsigned char)(length);
    pkt[9] = (unsigned char)(length >> 8);
    pkt[10] = (unsigned char)(length >> 16);
    pkt[11] = (unsigned char)(length >> 24);
    rc = libusb_bulk_transfer(d->handle, EP_SESSION, pkt, 20, &got,
                              d->timeout_ms);
    return (rc == 0 && got == 20) ? 0 : -1;
}

static int claim_ifaces(ft601_dev *d, char *err, size_t errlen)
{
    int rc;

    libusb_set_auto_detach_kernel_driver(d->handle, 1);
    rc = libusb_claim_interface(d->handle, 0);
    if (rc != 0) {
        snprintf(err, errlen, "claim IF0 failed (%s)", libusb_strerror(rc));
        return -1;
    }
    d->claimed0 = 1;
    rc = libusb_claim_interface(d->handle, 1);
    if (rc != 0) {
        snprintf(err, errlen, "claim IF1 failed (%s)", libusb_strerror(rc));
        return -1;
    }
    d->claimed1 = 1;
    d->ep_out = PIPE_OUT;
    d->ep_in = PIPE_IN;
    libusb_clear_halt(d->handle, EP_SESSION);
    libusb_clear_halt(d->handle, d->ep_out);
    libusb_clear_halt(d->handle, d->ep_in);
    return 0;
}

ft601_dev *ft601_open(int index, unsigned timeout_ms, char *err, size_t errlen)
{
    ft601_dev *d;
    libusb_device **list = NULL;
    ssize_t n, i;
    int match = 0;
    int rc;

    d = (ft601_dev *)calloc(1, sizeof(*d));
    if (!d) {
        set_err(err, errlen, "out of memory");
        return NULL;
    }
    d->timeout_ms = timeout_ms ? timeout_ms : 5000;
    ft601_bus_reset();

    rc = libusb_init(&d->ctx);
    if (rc != 0) {
        snprintf(err, errlen, "libusb_init failed (%s)", libusb_strerror(rc));
        free(d);
        return NULL;
    }

    n = libusb_get_device_list(d->ctx, &list);
    if (n < 0) {
        set_err(err, errlen, "libusb_get_device_list failed");
        libusb_exit(d->ctx);
        free(d);
        return NULL;
    }

    for (i = 0; i < n; i++) {
        struct libusb_device_descriptor desc;
        if (libusb_get_device_descriptor(list[i], &desc) != 0)
            continue;
        if (desc.idVendor != FT601_VID || desc.idProduct != FT601_PID)
            continue;
        if (match != index) {
            match++;
            continue;
        }
        rc = libusb_open(list[i], &d->handle);
        if (rc != 0) {
            snprintf(err, errlen, "libusb_open failed (%s)", libusb_strerror(rc));
            libusb_free_device_list(list, 1);
            libusb_exit(d->ctx);
            free(d);
            return NULL;
        }
        if (claim_ifaces(d, err, errlen) != 0) {
            if (d->claimed1)
                libusb_release_interface(d->handle, 1);
            if (d->claimed0)
                libusb_release_interface(d->handle, 0);
            libusb_close(d->handle);
            libusb_free_device_list(list, 1);
            libusb_exit(d->ctx);
            free(d);
            return NULL;
        }
        libusb_free_device_list(list, 1);
        return d;
    }

    libusb_free_device_list(list, 1);
    snprintf(err, errlen,
             "FT601 0403:601f index %d not found (saw %d). Board disconnected?",
             index, match);
    libusb_exit(d->ctx);
    free(d);
    return NULL;
}

void ft601_close(ft601_dev *d)
{
    if (!d)
        return;
    if (d->handle) {
        if (d->claimed1)
            libusb_release_interface(d->handle, 1);
        if (d->claimed0)
            libusb_release_interface(d->handle, 0);
        libusb_close(d->handle);
    }
    if (d->ctx)
        libusb_exit(d->ctx);
    free(d);
}

int ft601_write(ft601_dev *d, const void *buf, size_t n, size_t *xferred)
{
    size_t done = 0;
    const unsigned char *p = (const unsigned char *)buf;

    if (xferred)
        *xferred = 0;
    while (done < n) {
        size_t want = n - done;
        size_t chunk_done = 0;
        if (want > FT601_MAX_XFER)
            want = FT601_MAX_XFER;
        if (session_list(d, d->ep_out, (uint32_t)want) != 0) {
            if (xferred)
                *xferred = done;
            return -1;
        }
        while (chunk_done < want) {
            int got = 0;
            int rc = libusb_bulk_transfer(d->handle, d->ep_out,
                                          (unsigned char *)(p + done + chunk_done),
                                          (int)(want - chunk_done), &got,
                                          d->timeout_ms);
            if (got > 0)
                chunk_done += (size_t)got;
            if (rc != 0) {
                if (xferred)
                    *xferred = done + chunk_done;
                return -1;
            }
            if (got == 0)
                break;
        }
        done += chunk_done;
        if (chunk_done != want) {
            if (xferred)
                *xferred = done;
            return -1;
        }
    }
    if (xferred)
        *xferred = done;
    return 0;
}

int ft601_read(ft601_dev *d, void *buf, size_t n, size_t *xferred)
{
    size_t done = 0;
    unsigned char *p = (unsigned char *)buf;

    if (xferred)
        *xferred = 0;
    while (done < n) {
        size_t want = n - done;
        size_t chunk_done = 0;
        if (want > FT601_MAX_XFER)
            want = FT601_MAX_XFER;
        if (session_list(d, d->ep_in, (uint32_t)want) != 0) {
            if (xferred)
                *xferred = done;
            return -1;
        }
        while (chunk_done < want) {
            int got = 0;
            int rc = libusb_bulk_transfer(d->handle, d->ep_in,
                                          p + done + chunk_done,
                                          (int)(want - chunk_done), &got,
                                          d->timeout_ms);
            if (got > 0)
                chunk_done += (size_t)got;
            if (rc != 0) {
                if (xferred)
                    *xferred = done + chunk_done;
                return -1;
            }
            if (got == 0)
                break;
        }
        done += chunk_done;
        if (chunk_done != want) {
            if (xferred)
                *xferred = done;
            return -1;
        }
    }
    if (xferred)
        *xferred = done;
    return 0;
}

#endif
