"""Entry point. `python -m widgetsvc` prints the catalog; a name looks that one up."""

from __future__ import annotations

import sys

from widgetsvc.service import UnknownWidget, catalog, lookup


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if not args:
        for stock in catalog():
            print(f"{stock.name}\t{stock.quantity}")
        return 0
    try:
        stock = lookup(args[0])
    except UnknownWidget as exc:
        print(f"unknown widget: {exc.args[0]}", file=sys.stderr)
        return 1
    print(f"{stock.name}\t{stock.quantity}\t{'in stock' if stock.in_stock else 'out of stock'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
