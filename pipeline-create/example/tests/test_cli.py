from widgetsvc.__main__ import main


def test_no_args_prints_whole_catalog(capsys):
    assert main([]) == 0
    assert len(capsys.readouterr().out.strip().splitlines()) == 3


def test_known_widget_exits_zero(capsys):
    assert main(["flange"]) == 0
    assert "in stock" in capsys.readouterr().out


def test_unknown_widget_exits_one(capsys):
    assert main(["doohickey"]) == 1
    assert "unknown widget" in capsys.readouterr().err
