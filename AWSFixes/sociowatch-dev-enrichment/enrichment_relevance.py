"""Relevance rules shared by the SocioWatch enrichment Lambda."""


CONNECTED_ACCOUNT_REASON = (
    "Collected from a business account that the customer explicitly "
    "connected to SocioWatch."
)


def _clean(value):
    if value is None:
        return ""
    return str(value).strip()


def _as_boolean(value):
    if isinstance(value, bool):
        return value
    return _clean(value).lower() in {"1", "true", "yes", "y", "on"}


def preserve_connected_account_relevance(mention, enrichment):
    """Keep customer-connected Facebook and Instagram activity relevant.

    AI enrichment still supplies sentiment, priority, summaries, and other
    analysis. It is not allowed to hide activity collected directly from an
    account that the customer explicitly connected.

    The SourceCode/SourceType fallback repairs Meta records created before the
    explicit RelevanceLocked and RelevanceOrigin fields were introduced.
    """

    source_code = _clean(mention.get("SourceCode")).upper()
    source_type = _clean(mention.get("SourceType")).lower()
    relevance_origin = _clean(mention.get("RelevanceOrigin")).upper()
    relevance_locked = _as_boolean(mention.get("RelevanceLocked", False))
    is_connected_meta_activity = (
        source_code in {"FACEBOOK", "INSTAGRAM"}
        and source_type == "social"
    )

    if not (
        relevance_locked
        or relevance_origin == "CONNECTED_ACCOUNT"
        or is_connected_meta_activity
    ):
        return enrichment

    enrichment["IsRelevant"] = True
    enrichment["RelevanceScore"] = 100
    enrichment["RelevanceReason"] = CONNECTED_ACCOUNT_REASON
    return enrichment
