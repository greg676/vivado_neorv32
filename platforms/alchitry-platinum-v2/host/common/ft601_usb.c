/*
 * FT601 USB transport.
 *
 * Default: libusb-1.0 bulk IN/OUT on VID 0403 / PID 601f. The Ft+ EEPROM is
 * already 245 FIFO 32-bit, so D3XX is not required to move data.
 *
 * Optional: compile with -DFT601_USE_D3XX and link libftd3xx (needs
 * ftd3xx.h + libftd3xx.so unpacked, e.g. /opt/ftdi/d3xx).
 */

#include "ft601_usb.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FT601_VID 0x0403
#define FT601_PID 0x601f
#define PIPE_OUT  0x02
#define PIPE_IN   0x82

static void set_err(char *err, size_t errlen, const char *msg)
{
    if (err && errlen)
        snprintf(err, errlen, "%s", msg);
}

#ifdef FT601_USE_D3XX

#include "ftd3xx.h"

struct ft601_dev {
    FT_HANDLE handle;
    unsigned timeout_ms;
};

const char *ft601_backend_name(void)
{
    return "d3xx";
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
    if (d->handle)
        FT_Close(d->handle);
    free(d);
}

int ft601_write(ft601_dev *d, const void *buf, size_t n, size_t *xferred)
{
    ULONG got = 0;
    FT_STATUS st;

    if (xferred)
        *xferred = 0;
    st = FT_WritePipe(d->handle, PIPE_OUT, (PUCHAR)buf, (ULONG)n, &got, NULL);
    if (xferred)
        *xferred = (size_t)got;
    return (st == FT_OK && got == (ULONG)n) ? 0 : -1;
}

int ft601_read(ft601_dev *d, void *buf, size_t n, size_t *xferred)
{
    ULONG got = 0;
    FT_STATUS st;

    if (xferred)
        *xferred = 0;
    st = FT_ReadPipe(d->handle, PIPE_IN, (PUCHAR)buf, (ULONG)n, &got, NULL);
    if (xferred)
        *xferred = (size_t)got;
    return (st == FT_OK && got == (ULONG)n) ? 0 : -1;
}

#else /* libusb */

#include <libusb.h>

struct ft601_dev {
    libusb_context *ctx;
    libusb_device_handle *handle;
    unsigned char ep_out;
    unsigned char ep_in;
    int iface;
    unsigned timeout_ms;
};

const char *ft601_backend_name(void)
{
    return "libusb";
}

static int pick_bulk_pair(libusb_device *dev, int *iface, unsigned char *ep_out,
                          unsigned char *ep_in)
{
    struct libusb_config_descriptor *cfg = NULL;
    int rc, i, k;
    int found = -1;

    rc = libusb_get_active_config_descriptor(dev, &cfg);
    if (rc != 0 || !cfg)
        rc = libusb_get_config_descriptor(dev, 0, &cfg);
    if (rc != 0 || !cfg)
        return -1;

    for (i = 0; i < cfg->bNumInterfaces; i++) {
        const struct libusb_interface *intf = &cfg->interface[i];
        const struct libusb_interface_descriptor *alt;
        unsigned char out = 0, in = 0;

        if (intf->num_altsetting < 1)
            continue;
        alt = &intf->altsetting[0];
        for (k = 0; k < alt->bNumEndpoints; k++) {
            const struct libusb_endpoint_descriptor *ep = &alt->endpoint[k];
            if ((ep->bmAttributes & 0x3) != LIBUSB_TRANSFER_TYPE_BULK)
                continue;
            if (ep->bEndpointAddress & 0x80)
                in = ep->bEndpointAddress;
            else
                out = ep->bEndpointAddress;
        }
        if (out && in) {
            *iface = alt->bInterfaceNumber;
            *ep_out = out;
            *ep_in = in;
            found = 0;
            break;
        }
    }
    libusb_free_config_descriptor(cfg);
    return found;
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
    d->iface = -1;

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
        if (pick_bulk_pair(list[i], &d->iface, &d->ep_out, &d->ep_in) != 0) {
            set_err(err, errlen, "no bulk IN/OUT pair on FT601");
            libusb_close(d->handle);
            libusb_free_device_list(list, 1);
            libusb_exit(d->ctx);
            free(d);
            return NULL;
        }
        libusb_set_auto_detach_kernel_driver(d->handle, 1);
        rc = libusb_claim_interface(d->handle, d->iface);
        if (rc != 0) {
            snprintf(err, errlen, "claim interface %d failed (%s)", d->iface,
                     libusb_strerror(rc));
            libusb_close(d->handle);
            libusb_free_device_list(list, 1);
            libusb_exit(d->ctx);
            free(d);
            return NULL;
        }
        libusb_clear_halt(d->handle, d->ep_out);
        libusb_clear_halt(d->handle, d->ep_in);
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
        if (d->iface >= 0)
            libusb_release_interface(d->handle, d->iface);
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
        int got = 0;
        int rc = libusb_bulk_transfer(d->handle, d->ep_out,
                                      (unsigned char *)(p + done),
                                      (int)(n - done), &got, d->timeout_ms);
        if (got > 0)
            done += (size_t)got;
        if (rc != 0) {
            if (xferred)
                *xferred = done;
            return -1;
        }
        if (got == 0)
            break;
    }
    if (xferred)
        *xferred = done;
    return (done == n) ? 0 : -1;
}

int ft601_read(ft601_dev *d, void *buf, size_t n, size_t *xferred)
{
    size_t done = 0;
    unsigned char *p = (unsigned char *)buf;

    if (xferred)
        *xferred = 0;
    while (done < n) {
        int got = 0;
        int rc = libusb_bulk_transfer(d->handle, d->ep_in, p + done,
                                      (int)(n - done), &got, d->timeout_ms);
        if (got > 0)
            done += (size_t)got;
        if (rc != 0) {
            if (xferred)
                *xferred = done;
            return -1;
        }
        if (got == 0)
            break;
    }
    if (xferred)
        *xferred = done;
    return (done == n) ? 0 : -1;
}

#endif
