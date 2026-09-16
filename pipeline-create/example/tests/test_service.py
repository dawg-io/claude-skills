import pytest

from widgetsvc.service import UnknownWidget, catalog, lookup


def test_lookup_returns_quantity():
    assert lookup("sprocket").quantity == 12


def test_lookup_is_case_and_whitespace_insensitive():
    assert lookup("  SPROCKET ").name == "sprocket"


def test_lookup_rejects_unknown_widget():
    with pytest.raises(UnknownWidget):
        lookup("doohickey")


def test_zero_quantity_is_not_in_stock():
    assert lookup("grommet").in_stock is False


def test_catalog_is_sorted():
    names = [stock.name for stock in catalog()]
    assert names == sorted(names)
