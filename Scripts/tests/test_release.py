import base64
import importlib.machinery
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


loader = importlib.machinery.SourceFileLoader("xcodes_release", str(Path(__file__).resolve().parents[1] / "release"))
spec = importlib.util.spec_from_loader(loader.name, loader)
release = importlib.util.module_from_spec(spec)
loader.exec_module(release)

TAG = "v4.2.1b43"
URL = f"https://github.com/{release.APP}/releases/download/{TAG}/Xcodes.zip"
SIGNATURE = base64.b64encode(bytes(range(64))).decode()
METADATA = ("43", "4.2.1", SIGNATURE, "16")


def appcast(*enclosures):
    xml = ['<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>']
    for url, (build, version, signature, length) in enclosures:
        xml.append(
            f'<item><enclosure url="{url}" sparkle:version="{build}" sparkle:shortVersionString="{version}" '
            f'sparkle:edSignature="{signature}" length="{length}"/></item>'
        )
    return ("".join(xml) + "</channel></rss>").encode()


class ReleaseTests(unittest.TestCase):
    def test_build_uses_all_remote_tags_and_ignores_other_refs(self):
        refs = ["refs/heads/v4.2.1b99", "refs/tags/v4.2.0b42", "refs/tags/v9.0.0b7", "refs/tags/v9.1.0-beta"]
        self.assertEqual(release.next_build(refs), 43)
        self.assertEqual(release.next_build([]), 1)

    def test_signature_replaces_placeholders_without_changing_notes(self):
        note = "## Changes\r\n\r\n- Fix an issue\r\n\r\n<!-- sparkle:edSignature= -->\r\n"
        updated = release.signature_comment(note, SIGNATURE)
        self.assertTrue(updated.startswith("## Changes\r\n\r\n- Fix an issue"))
        self.assertEqual([item.strip() for item in release.COMMENT.findall(updated)], [SIGNATURE])
        self.assertEqual(release.signature_comment(updated, SIGNATURE), updated)

    def test_stable_and_prerelease_feeds(self):
        empty = appcast()
        full = appcast((URL, METADATA))
        release.validate_feeds(dict(zip(release.FEEDS, (full, full))), {"prerelease": False}, (URL, METADATA))
        release.validate_feeds(dict(zip(release.FEEDS, (empty, full))), {"prerelease": True}, (URL, METADATA))
        with self.assertRaisesRegex(release.ReleaseError, "stable feed"):
            release.validate_feeds(dict(zip(release.FEEDS, (full, full))), {"prerelease": True}, (URL, METADATA))
        with self.assertRaisesRegex(release.ReleaseError, "expected enclosure"):
            altered = appcast((URL, ("43", "4.2.1", SIGNATURE, "17")))
            release.validate_feeds(dict(zip(release.FEEDS, (full, altered))), {"prerelease": False}, (URL, METADATA))

    def test_website_rejects_regressions_in_either_feed(self):
        current = dict.fromkeys(release.FEEDS, appcast((URL, METADATA)))
        for name in release.FEEDS:
            candidate = dict(current, **{name: appcast()})
            with self.assertRaisesRegex(release.ReleaseError, name):
                release.preserve_feed_entries(current, candidate)

    def test_existing_uploaded_draft_asset_is_reused_only_if_digest_matches(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            archive = path / release.ARCHIVE
            archive.write_bytes(b"notarized zip")
            state = {
                "tag": TAG, "version": "4.2.1", "build": 43, "prerelease": False, "draft_id": 1,
                "draft_tag": "untagged-123", "signature": SIGNATURE, "size": archive.stat().st_size,
                "digest": release.sha256(archive),
            }
            asset = {"name": release.ARCHIVE, "state": "uploaded", "size": state["size"],
                     "digest": f"sha256:{state['digest']}"}
            draft = {"draft": True, "name": "4.2.1 (43)", "tag_name": TAG, "prerelease": False,
                     "body": release.signature_comment("Notes", SIGNATURE), "assets": [asset]}
            published = dict(draft, draft=False, html_url="https://example.test/release")
            with (
                patch.object(release, "github", side_effect=[draft, draft, draft, published]) as github,
                patch.object(release, "push_version"),
                patch.object(release, "remote_refs", return_value={f"refs/tags/{TAG}": "sha"}),
                patch.object(release, "run") as run,
            ):
                self.assertEqual(release.publish_release(path, state), published)
                run.assert_not_called()
                self.assertFalse(github.call_args.kwargs["body"]["draft"])

            asset["digest"] = "sha256:wrong"
            with (
                patch.object(release, "github", side_effect=[draft, draft, draft]) as github,
                patch.object(release, "push_version"),
                patch.object(release, "run") as run,
                self.assertRaisesRegex(release.ReleaseError, "SHA-256"),
            ):
                release.publish_release(path, state)
            run.assert_not_called()
            self.assertEqual(github.call_count, 3)

    def test_resume_after_deployment_failure_skips_publication(self):
        asset = {"name": release.ARCHIVE, "state": "uploaded", "size": 16, "digest": "sha256:abc",
                 "browser_download_url": URL}
        published = {"draft": False, "tag_name": TAG, "prerelease": False, "assets": [asset],
                     "body": release.signature_comment("Notes", SIGNATURE)}
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            path = folder / TAG
            path.mkdir()
            release.save_state(path, {"tag": TAG, "signature": SIGNATURE, "prerelease": False,
                                      "size": 16, "digest": "abc"})
            with (
                patch.object(release, "releases", side_effect=[[], [published]]),
                patch.object(release, "publish_release", return_value=published) as publish,
                patch.object(release, "sync_appcasts", side_effect=[release.ReleaseError("Pages failed"), None]) as sync,
            ):
                with self.assertRaisesRegex(release.ReleaseError, "Pages failed"):
                    release.finish(TAG, folder)
                self.assertFalse(release.read_state(path).get("complete", False))
                release.finish(TAG, folder)
                self.assertTrue(release.read_state(path)["complete"])
                publish.assert_called_once()
                self.assertEqual(sync.call_count, 2)


if __name__ == "__main__":
    unittest.main()
