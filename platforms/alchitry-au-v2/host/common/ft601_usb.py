"""FT601 USB transport: libusb first, optional D3XX fallback.

FT60x Function Protocol: claim IF0+IF1, 20-byte session list on EP 0x01,
then data on EP 0x02 / 0x82. That path wrote 13312 bytes on jetson-edge.
D3XX on Linux uses fifo id 0 (FT_WritePipeEx), not pipe 0x02.
"""

from __future__ import annotations

import ctypes
import os
import time
from ctypes import (
    POINTER,
    Structure,
    byref,
    c_int,
    c_uint,
    c_uint8,
    c_uint16,
    c_uint32,
    c_void_p,
    c_ulong,
)

FT601_VID = 0x0403
FT601_PID = 0x601F
PIPE_OUT = 0x02
PIPE_IN = 0x82
EP_SESSION = 0x01
FIFO_CH0 = 0
MAX_XFER = 16384
FT_OK = 0
FT_OPEN_BY_INDEX = 0x00000010
FT_PIPE_DIR_IN = 0
FT_PIPE_DIR_OUT = 1


class _FT_PIPE_TRANSFER_CONF(Structure):
    _fields_ = [
        ("fPipeNotUsed", c_int),
        ("fNonThreadSafeTransfer", c_int),
        ("bURBCount", c_uint8),
        ("wURBBufferCount", c_uint16),
        ("dwURBBufferSize", c_uint32),
        ("dwStreamingSize", c_uint32),
    ]


class _FT_TRANSFER_CONF(Structure):
    _fields_ = [
        ("wStructSize", c_uint16),
        ("pipe", _FT_PIPE_TRANSFER_CONF * 2),
        ("fStopReadingOnURBUnderrun", c_int),
        ("fBitBangMode", c_int),
        ("fKeepDeviceSideBufferAfterReopen", c_int),
    ]

LIBUSB_TRANSFER_TYPE_BULK = 2
LIBUSB_SUCCESS = 0


class _DeviceDescriptor(Structure):
    _fields_ = [
        ("bLength", c_uint8),
        ("bDescriptorType", c_uint8),
        ("bcdUSB", c_uint16),
        ("bDeviceClass", c_uint8),
        ("bDeviceSubClass", c_uint8),
        ("bDeviceProtocol", c_uint8),
        ("bMaxPacketSize0", c_uint8),
        ("idVendor", c_uint16),
        ("idProduct", c_uint16),
        ("bcdDevice", c_uint16),
        ("iManufacturer", c_uint8),
        ("iProduct", c_uint8),
        ("iSerialNumber", c_uint8),
        ("bNumConfigurations", c_uint8),
    ]


class _EndpointDesc(Structure):
    _fields_ = [
        ("bLength", c_uint8),
        ("bDescriptorType", c_uint8),
        ("bEndpointAddress", c_uint8),
        ("bmAttributes", c_uint8),
        ("wMaxPacketSize", c_uint16),
        ("bInterval", c_uint8),
        ("bRefresh", c_uint8),
        ("bSynchAddress", c_uint8),
        ("extra", c_void_p),
        ("extra_length", c_int),
    ]


class _InterfaceDesc(Structure):
    pass


class _Interface(Structure):
    _fields_ = [
        ("altsetting", POINTER(_InterfaceDesc)),
        ("num_altsetting", c_int),
    ]


class _ConfigDesc(Structure):
    _fields_ = [
        ("bLength", c_uint8),
        ("bDescriptorType", c_uint8),
        ("wTotalLength", c_uint16),
        ("bNumInterfaces", c_uint8),
        ("bConfigurationValue", c_uint8),
        ("iConfiguration", c_uint8),
        ("bmAttributes", c_uint8),
        ("MaxPower", c_uint8),
        ("interface", POINTER(_Interface)),
        ("extra", c_void_p),
        ("extra_length", c_int),
    ]


_InterfaceDesc._fields_ = [
    ("bLength", c_uint8),
    ("bDescriptorType", c_uint8),
    ("bInterfaceNumber", c_uint8),
    ("bAlternateSetting", c_uint8),
    ("bNumEndpoints", c_uint8),
    ("bInterfaceClass", c_uint8),
    ("bInterfaceSubClass", c_uint8),
    ("bInterfaceProtocol", c_uint8),
    ("iInterface", c_uint8),
    ("endpoint", POINTER(_EndpointDesc)),
    ("extra", c_void_p),
    ("extra_length", c_int),
]


def _load_libusb() -> ctypes.CDLL:
    names = [os.environ.get("LIBUSB_LIB"), "libusb-1.0.so.0", "libusb-1.0.so",
             "libusb-1.0.dylib"]
    last = None
    for name in names:
        if not name:
            continue
        try:
            lib = ctypes.CDLL(name)
            break
        except OSError as exc:
            last = exc
            lib = None
    else:
        lib = None
    if lib is None:
        raise FileNotFoundError(f"libusb-1.0 not found ({last})")
    lib.libusb_init.argtypes = [POINTER(c_void_p)]
    lib.libusb_init.restype = c_int
    lib.libusb_exit.argtypes = [c_void_p]
    lib.libusb_get_device_list.argtypes = [c_void_p, POINTER(POINTER(c_void_p))]
    lib.libusb_get_device_list.restype = ctypes.c_ssize_t
    lib.libusb_free_device_list.argtypes = [POINTER(c_void_p), c_int]
    lib.libusb_get_device_descriptor.argtypes = [c_void_p, POINTER(_DeviceDescriptor)]
    lib.libusb_get_device_descriptor.restype = c_int
    lib.libusb_open.argtypes = [c_void_p, POINTER(c_void_p)]
    lib.libusb_open.restype = c_int
    lib.libusb_close.argtypes = [c_void_p]
    lib.libusb_open_device_with_vid_pid.argtypes = [c_void_p, c_uint16, c_uint16]
    lib.libusb_open_device_with_vid_pid.restype = c_void_p
    lib.libusb_reset_device.argtypes = [c_void_p]
    lib.libusb_reset_device.restype = c_int
    lib.libusb_set_auto_detach_kernel_driver.argtypes = [c_void_p, c_int]
    lib.libusb_claim_interface.argtypes = [c_void_p, c_int]
    lib.libusb_claim_interface.restype = c_int
    lib.libusb_release_interface.argtypes = [c_void_p, c_int]
    lib.libusb_clear_halt.argtypes = [c_void_p, c_uint8]
    lib.libusb_bulk_transfer.argtypes = [c_void_p, c_uint8, ctypes.c_void_p, c_int,
                                         POINTER(c_int), c_uint]
    lib.libusb_bulk_transfer.restype = c_int
    lib.libusb_get_active_config_descriptor.argtypes = [c_void_p,
                                                        POINTER(POINTER(_ConfigDesc))]
    lib.libusb_get_active_config_descriptor.restype = c_int
    lib.libusb_get_config_descriptor.argtypes = [c_void_p, c_uint8,
                                                 POINTER(POINTER(_ConfigDesc))]
    lib.libusb_get_config_descriptor.restype = c_int
    lib.libusb_free_config_descriptor.argtypes = [POINTER(_ConfigDesc)]
    lib.libusb_strerror.argtypes = [c_int]
    lib.libusb_strerror.restype = ctypes.c_char_p
    return lib


def _bus_reset() -> None:
    lib = _load_libusb()
    ctx = c_void_p()
    if lib.libusb_init(byref(ctx)) != 0:
        return
    h = lib.libusb_open_device_with_vid_pid(ctx, FT601_VID, FT601_PID)
    if h:
        lib.libusb_reset_device(h)
        lib.libusb_close(h)
    lib.libusb_exit(ctx)
    time.sleep(1.2)


class Ft601Libusb:
    name = "libusb"

    def __init__(self, index: int = 0, timeout_ms: int = 5000):
        self.lib = _load_libusb()
        self.ctx = c_void_p()
        self.handle = c_void_p()
        self.claimed0 = False
        self.claimed1 = False
        self.sess = 0
        self.ep_out = PIPE_OUT
        self.ep_in = PIPE_IN
        self.timeout_ms = timeout_ms
        _bus_reset()
        rc = self.lib.libusb_init(byref(self.ctx))
        if rc != 0:
            raise RuntimeError(f"libusb_init failed ({rc})")
        lst = POINTER(c_void_p)()
        n = self.lib.libusb_get_device_list(self.ctx, byref(lst))
        if n < 0:
            self.lib.libusb_exit(self.ctx)
            raise RuntimeError("libusb_get_device_list failed")
        match = 0
        opened = False
        try:
            for i in range(n):
                desc = _DeviceDescriptor()
                if self.lib.libusb_get_device_descriptor(lst[i], byref(desc)) != 0:
                    continue
                if desc.idVendor != FT601_VID or desc.idProduct != FT601_PID:
                    continue
                if match != index:
                    match += 1
                    continue
                rc = self.lib.libusb_open(lst[i], byref(self.handle))
                if rc != 0:
                    raise RuntimeError(
                        f"libusb_open failed ({self.lib.libusb_strerror(rc).decode()})"
                    )
                self.lib.libusb_set_auto_detach_kernel_driver(self.handle, 1)
                rc = self.lib.libusb_claim_interface(self.handle, 0)
                if rc != 0:
                    raise RuntimeError(
                        f"claim IF0 failed ({self.lib.libusb_strerror(rc).decode()})"
                    )
                self.claimed0 = True
                rc = self.lib.libusb_claim_interface(self.handle, 1)
                if rc != 0:
                    raise RuntimeError(
                        f"claim IF1 failed ({self.lib.libusb_strerror(rc).decode()})"
                    )
                self.claimed1 = True
                self.lib.libusb_clear_halt(self.handle, c_uint8(EP_SESSION))
                self.lib.libusb_clear_halt(self.handle, c_uint8(self.ep_out))
                self.lib.libusb_clear_halt(self.handle, c_uint8(self.ep_in))
                opened = True
                break
        finally:
            self.lib.libusb_free_device_list(lst, 1)
        if not opened:
            self.lib.libusb_exit(self.ctx)
            raise FileNotFoundError(
                f"FT601 0403:601f index {index} not found (saw {match}). "
                "Board disconnected?"
            )

    def _session(self, pipe: int, length: int) -> None:
        self.sess = (self.sess + 1) & 0xFFFFFFFF
        pkt = bytearray(20)
        pkt[0:4] = self.sess.to_bytes(4, "little")
        pkt[4] = pipe & 0xFF
        pkt[8:12] = int(length).to_bytes(4, "little")
        buf = ctypes.create_string_buffer(bytes(pkt), 20)
        got = c_int(0)
        rc = self.lib.libusb_bulk_transfer(
            self.handle, c_uint8(EP_SESSION), buf, 20, byref(got), self.timeout_ms
        )
        if rc != 0 or got.value != 20:
            raise RuntimeError(f"session EP 0x01 {rc} got={got.value}")

    def close(self) -> None:
        if self.handle:
            if self.claimed1:
                self.lib.libusb_release_interface(self.handle, 1)
            if self.claimed0:
                self.lib.libusb_release_interface(self.handle, 0)
            self.lib.libusb_close(self.handle)
            self.handle = c_void_p()
        if self.ctx:
            self.lib.libusb_exit(self.ctx)
            self.ctx = c_void_p()

    def write(self, data: bytes) -> int:
        done = 0
        while done < len(data):
            want = min(MAX_XFER, len(data) - done)
            self._session(self.ep_out, want)
            chunk_done = 0
            while chunk_done < want:
                chunk = data[done + chunk_done : done + want]
                buf = ctypes.create_string_buffer(chunk, len(chunk))
                got = c_int(0)
                rc = self.lib.libusb_bulk_transfer(
                    self.handle, c_uint8(self.ep_out), buf, len(chunk),
                    byref(got), self.timeout_ms,
                )
                if got.value > 0:
                    chunk_done += int(got.value)
                if rc != 0:
                    raise RuntimeError(
                        f"libusb bulk OUT {rc} ({done + chunk_done} of {len(data)})"
                    )
                if got.value == 0:
                    break
            done += chunk_done
            if chunk_done != want:
                raise RuntimeError(f"short write {done} of {len(data)}")
        return done

    def read(self, nbytes: int) -> bytes:
        out = bytearray()
        while len(out) < nbytes:
            want = min(MAX_XFER, nbytes - len(out))
            self._session(self.ep_in, want)
            chunk = bytearray()
            while len(chunk) < want:
                buf = ctypes.create_string_buffer(want - len(chunk))
                got = c_int(0)
                rc = self.lib.libusb_bulk_transfer(
                    self.handle, c_uint8(self.ep_in), buf, want - len(chunk),
                    byref(got), self.timeout_ms,
                )
                if got.value > 0:
                    chunk += buf.raw[: int(got.value)]
                if rc != 0:
                    raise RuntimeError(
                        f"libusb bulk IN {rc} ({len(out) + len(chunk)} of {nbytes})"
                    )
                if got.value == 0:
                    break
            out += chunk
            if len(chunk) != want:
                raise RuntimeError(f"short read {len(out)} of {nbytes}")
        return bytes(out)


class Ft601D3xx:
    name = "d3xx"

    def __init__(self, index: int = 0, timeout_ms: int = 5000, skip_reset: bool = False):
        names = [
            os.environ.get("FTD3XX_LIB"),
            "/opt/ftdi/d3xx/libftd3xx.so",
            "libftd3xx.so",
            "libftd3xx.dylib",
            "FTD3XX.dll",
        ]
        last = None
        lib = None
        for name in names:
            if not name:
                continue
            try:
                lib = ctypes.CDLL(name)
                break
            except OSError as exc:
                last = exc
        if lib is None:
            raise FileNotFoundError(
                "D3XX library not found. Unpack the FTDI Linux D3XX SDK to "
                "/opt/ftdi/d3xx (ftd3xx.h + libftd3xx.so) or set FTD3XX_LIB. "
                f"Last error: {last}"
            )
        lib.FT_Create.argtypes = [c_void_p, c_ulong, POINTER(c_void_p)]
        lib.FT_Create.restype = c_ulong
        lib.FT_Close.argtypes = [c_void_p]
        lib.FT_Close.restype = c_ulong
        lib.FT_WritePipeEx.argtypes = [c_void_p, c_uint8, ctypes.c_void_p, c_ulong,
                                       POINTER(c_ulong), c_ulong]
        lib.FT_WritePipeEx.restype = c_ulong
        lib.FT_ReadPipeEx.argtypes = [c_void_p, c_uint8, ctypes.c_void_p, c_ulong,
                                      POINTER(c_ulong), c_ulong]
        lib.FT_ReadPipeEx.restype = c_ulong
        lib.FT_SetPipeTimeout.argtypes = [c_void_p, c_uint8, c_ulong]
        lib.FT_SetPipeTimeout.restype = c_ulong
        lib.FT_SetTransferParams.argtypes = [c_void_p, c_ulong]
        lib.FT_SetTransferParams.restype = c_ulong
        self.lib = lib
        self.handle = c_void_p()
        self.timeout_ms = timeout_ms
        if not skip_reset:
            _bus_reset()
        conf = _FT_TRANSFER_CONF()
        conf.wStructSize = ctypes.sizeof(_FT_TRANSFER_CONF)
        conf.pipe[FT_PIPE_DIR_IN].fNonThreadSafeTransfer = 1
        conf.pipe[FT_PIPE_DIR_OUT].fNonThreadSafeTransfer = 1
        for fifo in range(4):
            lib.FT_SetTransferParams(ctypes.byref(conf), fifo)
        st = lib.FT_Create(c_void_p(index), FT_OPEN_BY_INDEX, byref(self.handle))
        if st != FT_OK or not self.handle.value:
            raise RuntimeError(f"FT_Create index {index} failed ({st})")
        lib.FT_SetPipeTimeout(self.handle, PIPE_OUT, timeout_ms)
        lib.FT_SetPipeTimeout(self.handle, PIPE_IN, timeout_ms)

    def close(self) -> None:
        if self.handle:
            self.lib.FT_Close(self.handle)
            self.handle = c_void_p()

    def write(self, data: bytes) -> int:
        done = 0
        while done < len(data):
            want = min(MAX_XFER, len(data) - done)
            xferred = c_ulong(0)
            chunk = data[done : done + want]
            st = self.lib.FT_WritePipeEx(
                self.handle, FIFO_CH0, chunk, want, byref(xferred), self.timeout_ms
            )
            done += int(xferred.value)
            if st != FT_OK or xferred.value != want:
                raise RuntimeError(
                    f"FT_WritePipeEx {st} ({done} of {len(data)})"
                )
        return done

    def read(self, nbytes: int) -> bytes:
        out = bytearray()
        while len(out) < nbytes:
            want = min(MAX_XFER, nbytes - len(out))
            rx = ctypes.create_string_buffer(want)
            xferred = c_ulong(0)
            st = self.lib.FT_ReadPipeEx(
                self.handle, FIFO_CH0, rx, want, byref(xferred), self.timeout_ms
            )
            if xferred.value:
                out += rx.raw[: int(xferred.value)]
            if st != FT_OK or int(xferred.value) != want:
                raise RuntimeError(f"FT_ReadPipeEx {st} ({len(out)} of {nbytes})")
        return bytes(out)


def prime_ft60x_session(nbytes: int = 16384, timeout_ms: int = 5000) -> None:
    """FT60x Function Protocol session on EP 0x01, then drop libusb so D3XX can open."""
    try:
        dev = Ft601Libusb(timeout_ms=timeout_ms)
    except (FileNotFoundError, OSError, RuntimeError) as exc:
        print(f"FT601 session : skipped ({exc})")
        return
    try:
        dev._session(PIPE_OUT, nbytes)
        dev._session(PIPE_IN, nbytes)
        print(f"FT601 session : primed OUT+IN {nbytes} bytes")
    except RuntimeError as exc:
        print(f"FT601 session : {exc}")
    finally:
        dev.close()


def open_ft601(index: int = 0, timeout_ms: int = 5000, backend: str = "auto"):
    """backend: auto (libusb then d3xx), libusb, or d3xx (session then D3XX)."""
    errors = []
    order = []
    if backend == "d3xx":
        prime_ft60x_session(nbytes=16384, timeout_ms=timeout_ms)
        try:
            dev = Ft601D3xx(index=index, timeout_ms=timeout_ms, skip_reset=True)
            print(f"FT601 backend : {dev.name}")
            return dev
        except (FileNotFoundError, OSError, RuntimeError) as exc:
            errors.append(f"{Ft601D3xx.name} (no extra reset): {exc}")
        try:
            time.sleep(1.0)
            dev = Ft601D3xx(index=index, timeout_ms=timeout_ms, skip_reset=False)
            print(f"FT601 backend : {dev.name} (after USB reset)")
            return dev
        except (FileNotFoundError, OSError, RuntimeError) as exc:
            errors.append(f"{Ft601D3xx.name}: {exc}")
            raise FileNotFoundError(
                "Could not open FT601 D3XX after session.\n  " + "\n  ".join(errors)
            ) from exc
    elif backend == "libusb":
        order = [Ft601Libusb]
    else:
        order = [Ft601Libusb, Ft601D3xx]
    for cls in order:
        try:
            dev = cls(index=index, timeout_ms=timeout_ms)
            print(f"FT601 backend : {dev.name}")
            return dev
        except FileNotFoundError as exc:
            errors.append(f"{cls.name}: {exc}")
        except OSError as exc:
            errors.append(f"{cls.name}: {exc}")
        except RuntimeError as exc:
            errors.append(f"{cls.name}: {exc}")
    raise FileNotFoundError(
        "Could not open FT601. Tried libusb then D3XX.\n  " + "\n  ".join(errors) +
        "\nInstall libusb-1.0 (preferred) or unpack D3XX to /opt/ftdi/d3xx."
    )
