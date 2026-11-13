# GUI memory verification

Historical GUI measurements (2026-11-02), not a benchmark of this split.

The GUI now prefers Mesa when a non-NVIDIA GPU exists, unless the user set
`__EGL_VENDOR_LIBRARY_FILENAMES`. Session-wide `__GLX_VENDOR_LIBRARY_NAME` and
`__NV_PRIME_RENDER_OFFLOAD` are replaced for the GUI, because they kept NVIDIA loaded. In a nested session the About page went from 437 MiB RSS and
152 MiB PSS to 306 MiB RSS and 108 MiB PSS, with no NVIDIA libraries mapped.
