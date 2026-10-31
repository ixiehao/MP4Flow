import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('validator', Path(__file__).resolve().parents[1] / 'validate_localizations.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class LocalizationValidatorTests(unittest.TestCase):
    def test_all_shipped_catalogs_match(self):
        languages, keys = validator.validate(Path(__file__).resolve().parents[2])
        self.assertEqual(languages, 7)
        self.assertGreaterEqual(keys, 405)

    def test_positional_arguments_preserve_types(self):
        self.assertEqual(validator.signature('%d: %@ %.1f%%'), validator.signature('%2$@ %3$.1f%% %1$d'))
        self.assertNotEqual(validator.signature('%d %@'), validator.signature('%@ %d'))
        with self.assertRaises(ValueError):
            validator.signature('%1$d %@')

    def test_duplicate_keys_rejected_even_when_plutil_accepts_them(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Localizable.strings'
            path.write_text('/* "ignored" = "comment"; */\n"key" = "one";\n"key" = "two";')
            with self.assertRaisesRegex(ValueError, 'duplicate'):
                validator.load_catalog(path)

    def test_empty_or_malformed_translations_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Localizable.strings'
            path.write_text('"key" = "";')
            with self.assertRaisesRegex(ValueError, 'empty'):
                validator.load_catalog(path)
