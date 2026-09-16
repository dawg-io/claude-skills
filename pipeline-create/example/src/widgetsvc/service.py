"""Widget lookup, kept deliberately boring so the tests are the interesting part."""

from __future__ import annotations

from dataclasses import dataclass

_CATALOG: dict[str, int] = {
    "sprocket": 12,
    "flange": 3,
    "grommet": 0,
}


class UnknownWidget(KeyError):
    """Raised when a widget name is not in the catalog."""


@dataclass(frozen=True)
class Stock:
    name: str
    quantity: int

    @property
    def in_stock(self) -> bool:
        return self.quantity > 0


def lookup(name: str) -> Stock:
    """Return the stock record for ``name``.

    Names are matched case-insensitively and with surrounding whitespace stripped,
    because the callers upstream are not careful about either.
    """
    key = name.strip().lower()
    if key not in _CATALOG:
        raise UnknownWidget(name)
    return Stock(name=key, quantity=_CATALOG[key])


def catalog() -> list[Stock]:
    """Every widget, sorted by name."""
    return [Stock(name=n, quantity=q) for n, q in sorted(_CATALOG.items())]
