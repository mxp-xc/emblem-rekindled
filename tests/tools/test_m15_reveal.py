import json
import tempfile
import unittest
from pathlib import Path

from emblem_dev.content.configuration import normalize_deployment


class RevealTests(unittest.TestCase):
    def test_reveals_only_declared_hidden_units_and_rejects_bad_ids(self):
        with tempfile.TemporaryDirectory() as directory:
            chapter = Path(directory)
            authored = chapter / "authored/battles/m15.json"
            authored.parent.mkdir(parents=True)
            deployment = {
                "battleId": "m15",
                "width": 2,
                "height": 2,
                "units": [
                    {"sourceId": 45, "flags": 1, "faction": 1},
                    {"sourceId": 46, "flags": 1, "faction": 1},
                    {"sourceId": 47, "flags": 0, "faction": 1},
                ],
            }
            authored.write_text(json.dumps({"deploymentRevealUnitIds": [45]}))
            result = normalize_deployment(chapter, deployment)
            self.assertEqual([row["flags"] for row in result["units"]], [0, 1, 0])
            self.assertEqual(deployment["units"][0]["flags"], 1)
            authored.write_text(json.dumps({"deploymentRevealUnitIds": [45]}))
            self.assertEqual(normalize_deployment(chapter, result), result)
            for identities in ([45, 45], [99], [True]):
                authored.write_text(json.dumps({"deploymentRevealUnitIds": identities}))
                with self.subTest(identities=identities), self.assertRaises(ValueError):
                    normalize_deployment(chapter, deployment)


if __name__ == "__main__":
    unittest.main()
