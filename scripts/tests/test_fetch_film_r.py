import hashlib
import importlib.util
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/defect-corpus/fetch-film-r.py"
SPEC = importlib.util.spec_from_file_location("fetch_film_r", SCRIPT)
assert SPEC and SPEC.loader
fetch_film_r = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fetch_film_r)


class FetchFilmRArchiveTests(unittest.TestCase):
    def test_extract_archive_verifies_and_writes_pinned_files(self):
        payloads = {
            "sample.jpg": b"damaged",
            "sample_restored.jpg": b"restored",
        }
        items = [
            {
                "name": name,
                "size": len(data),
                "supplied_md5": hashlib.md5(data).hexdigest(),
            }
            for name, data in payloads.items()
        ]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "corpus.zip"
            output = root / "output"
            output.mkdir()
            with zipfile.ZipFile(archive, "w") as target:
                for name, data in payloads.items():
                    target.writestr(name, data)

            fetch_film_r.extract_archive(archive, items, output)

            for name, data in payloads.items():
                self.assertEqual((output / name).read_bytes(), data)

    def test_extract_archive_rejects_unexpected_members(self):
        data = b"damaged"
        item = {
            "name": "sample.jpg",
            "size": len(data),
            "supplied_md5": hashlib.md5(data).hexdigest(),
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "corpus.zip"
            output = root / "output"
            output.mkdir()
            with zipfile.ZipFile(archive, "w") as target:
                target.writestr("sample.jpg", data)
                target.writestr("../unexpected.jpg", b"unsafe")

            with self.assertRaisesRegex(RuntimeError, "unexpected file"):
                fetch_film_r.extract_archive(archive, [item], output)


if __name__ == "__main__":
    unittest.main()
