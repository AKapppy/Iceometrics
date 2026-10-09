import datetime as dt
import unittest

from hockey_app.data.xml_cache import _ordered_labels_in_range


class XmlCacheDateOrderTests(unittest.TestCase):
    def test_month_day_labels_sort_across_month_boundary(self):
        labels = ["10/1", "10/2", "10/3", "10/4", "9/29", "9/30"]
        ordered = _ordered_labels_in_range(
            labels,
            start=dt.date(2026, 9, 29),
            end=dt.date(2026, 10, 4),
        )
        self.assertEqual(
            ordered,
            ["9/29", "9/30", "10/1", "10/2", "10/3", "10/4"],
        )


if __name__ == "__main__":
    unittest.main()
