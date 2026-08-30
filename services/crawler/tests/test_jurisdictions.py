import unittest

from migration_crawler.jurisdictions import JURISDICTION_LABELS, label_for


class JurisdictionLabelTests(unittest.TestCase):
    def test_覆盖八个州领地加联邦(self):
        # 只覆盖「当前接入的」会在下次扩张时重演同一次事故。
        self.assertEqual(len(JURISDICTION_LABELS), 9)
        for code in ["AU-SA", "AU-QLD", "AU-NSW", "AU-VIC", "AU-WA",
                     "AU-TAS", "AU-NT", "AU-ACT", "AU-FED"]:
            self.assertTrue(label_for(code))

    def test_各辖区标签互不相同(self):
        self.assertEqual(len(set(JURISDICTION_LABELS.values())), len(JURISDICTION_LABELS))

    def test_未知辖区抛错而不是退回默认值(self):
        # 事故的形态就是「退回默认值」：写死的 "南澳" 让 47 条非南澳内容
        # 带着错误标签入库。错误的标签比没有标签危险，因为它看起来是对的。
        with self.assertRaises(ValueError):
            label_for("AU-XYZ")
        with self.assertRaises(ValueError):
            label_for("")


if __name__ == "__main__":
    unittest.main()
