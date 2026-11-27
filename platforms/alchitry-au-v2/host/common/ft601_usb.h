#ifndef FT601_USB_H
#define FT601_USB_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ft601_dev ft601_dev;

/* D3XX IN stream: 256 KiB .. 1 MiB URBs (FT_ReadPipeAsync max is 1 MiB). */
#define FT601_STREAM_CHUNK_MIN (256u * 1024u)
#define FT601_STREAM_CHUNK_MAX (1024u * 1024u)
#define FT601_STREAM_FLIGHT_MAX 8u

/* Open the Nth FT601 (VID 0403 PID 601f). timeout_ms is the bulk timeout.
 * On failure returns NULL and writes a NUL-terminated message to err. */
ft601_dev *ft601_open(int index, unsigned timeout_ms, char *err, size_t errlen);
void ft601_close(ft601_dev *d);

/* Full-size bulk transfer. Returns 0 on success. xferred may be NULL. */
int ft601_write(ft601_dev *d, const void *buf, size_t n, size_t *xferred);
int ft601_read(ft601_dev *d, void *buf, size_t n, size_t *xferred);

/*
 * D3XX IN: FT_SetStreamPipe + overlapped FT_ReadPipeAsync (several URBs in
 * flight). chunk_bytes must be 256 KiB..1 MiB. nflight is 2..8.
 * No-op / -1 on the libusb backend (16 KiB session URBs stay as they are).
 */
int ft601_configure_in_stream(ft601_dev *d, unsigned chunk_bytes,
                              unsigned nflight, char *err, size_t errlen);

/* "d3xx-overlapped", "d3xx-stream", "d3xx-oneshot", or "libusb". */
const char *ft601_in_path(const ft601_dev *d);

const char *ft601_backend_name(void);

#ifdef __cplusplus
}
#endif

#endif /* FT601_USB_H */
