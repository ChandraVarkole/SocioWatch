import unittest

from enrichment_relevance import (
    CONNECTED_ACCOUNT_REASON,
    preserve_connected_account_relevance,
)


class PreserveConnectedAccountRelevanceTests(unittest.TestCase):
    def test_locked_facebook_activity_remains_relevant(self):
        enrichment = {
            "IsRelevant": False,
            "RelevanceScore": 12,
            "RelevanceReason": "No company keyword was found.",
            "Sentiment": "Neutral",
        }

        result = preserve_connected_account_relevance(
            {
                "SourceCode": "FACEBOOK",
                "SourceType": "social",
                "RelevanceOrigin": "CONNECTED_ACCOUNT",
                "RelevanceLocked": True,
            },
            enrichment,
        )

        self.assertTrue(result["IsRelevant"])
        self.assertEqual(result["RelevanceScore"], 100)
        self.assertEqual(result["RelevanceReason"], CONNECTED_ACCOUNT_REASON)
        self.assertEqual(result["Sentiment"], "Neutral")

    def test_legacy_instagram_activity_is_repaired(self):
        result = preserve_connected_account_relevance(
            {"SourceCode": "INSTAGRAM", "SourceType": "social"},
            {"IsRelevant": False},
        )

        self.assertTrue(result["IsRelevant"])

    def test_unrelated_web_mention_keeps_ai_relevance(self):
        enrichment = {
            "IsRelevant": False,
            "RelevanceScore": 8,
            "RelevanceReason": "Unrelated result.",
        }

        result = preserve_connected_account_relevance(
            {"SourceCode": "WEB", "SourceType": "web"},
            enrichment,
        )

        self.assertEqual(result, enrichment)
        self.assertFalse(result["IsRelevant"])


if __name__ == "__main__":
    unittest.main()
