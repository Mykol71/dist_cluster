"""Shared deterministic matrix definitions for workers and verification."""

DEFAULT_MATRIX_SIZE = 600
DEFAULT_MATRIX_SEED = 20260726
VALUE_MODULUS = 1000


def build_matrix_a(size, seed, numpy_module=None):
    """Build matrix A identically on every supported node."""
    if numpy_module is not None:
        rows = numpy_module.arange(size, dtype=numpy_module.int64)[:, None]
        columns = numpy_module.arange(size, dtype=numpy_module.int64)[None, :]
        return ((rows * 17 + columns * 31 + seed) % VALUE_MODULUS) / VALUE_MODULUS

    return [
        [
            ((row * 17 + column * 31 + seed) % VALUE_MODULUS) / VALUE_MODULUS
            for column in range(size)
        ]
        for row in range(size)
    ]


def build_matrix_b(size, seed, numpy_module=None):
    """Build matrix B identically on every supported node."""
    if numpy_module is not None:
        rows = numpy_module.arange(size, dtype=numpy_module.int64)[:, None]
        columns = numpy_module.arange(size, dtype=numpy_module.int64)[None, :]
        return (
            (rows * 29 + columns * 13 + seed + 97) % VALUE_MODULUS
        ) / VALUE_MODULUS

    return [
        [
            ((row * 29 + column * 13 + seed + 97) % VALUE_MODULUS)
            / VALUE_MODULUS
            for column in range(size)
        ]
        for row in range(size)
    ]
