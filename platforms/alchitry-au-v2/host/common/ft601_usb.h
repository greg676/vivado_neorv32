#ifndef FT601_USB_H
#define FT601_USB_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ft601_dev ft601_dev;

/* Open the Nth FT601 (VID 0403 PID 601f). timeout_ms is the bulk timeout.
 * On failure returns NULL and writes a NUL-terminated message to err. */
ft601_dev *ft601_open(int index, unsigned timeout_ms, char *err, size_t errlen);
void ft601_close(ft601_dev *d);

/* Full-size bulk transfer. Returns 0 on success. xferred may be NULL. */
int ft601_write(ft601_dev *d, const void *buf, size_t n, size_t *xferred);
int ft601_read(ft601_dev *d, void *buf, size_t n, size_t *xferred);

const char *ft601_backend_name(void);

#ifdef __cplusplus
}
#endif

#endif /* FT601_USB_H */
