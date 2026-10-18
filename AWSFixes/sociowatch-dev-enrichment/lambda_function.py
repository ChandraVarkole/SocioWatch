import json
import logging
import os
import re
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Attr

from enrichment_relevance import preserve_connected_account_relevance


logger = logging.getLogger()
logger.setLevel(logging.INFO)


# ---------------------------------------------------------
# Configuration
# ---------------------------------------------------------

MENTIONS_TABLE_NAME = os.environ.get(
    "MENTIONS_TABLE",
    "sociowatch-dev-mentions"
)

BEDROCK_MODEL_ID = os.environ.get(
    "BEDROCK_MODEL_ID",
    "us.amazon.nova-lite-v1:0"
)

AWS_REGION = os.environ.get(
    "AWS_REGION",
    "us-east-2"
)

MAX_ITEMS_PER_RUN = 25

MAX_INPUT_CHARACTERS = 6000

MAX_OUTPUT_TOKENS = 1100

ENRICHMENT_VERSION = "v6"

EXECUTIVE_SUMMARY_FUNCTION = os.environ.get(
    "EXECUTIVE_SUMMARY_FUNCTION",
    "sociowatch-dev-executive-summary"
)

ALLOWED_RELEVANCE_RULES = (
    "COMPANY_AND_KEYWORD",
    "COMPANY_IDENTITY",
)


# ---------------------------------------------------------
# AWS
# ---------------------------------------------------------

dynamodb = boto3.resource(
    "dynamodb",
    region_name=AWS_REGION
)

mentions_table = dynamodb.Table(
    MENTIONS_TABLE_NAME
)

bedrock = boto3.client(
    "bedrock-runtime",
    region_name=AWS_REGION
)

lambda_client = boto3.client(
    "lambda",
    region_name=AWS_REGION
)


# ---------------------------------------------------------
# Lambda Handler
# ---------------------------------------------------------

def lambda_handler(event, context):

    event = normalize_event(
        event
    )

    requested_max = event.get(
        "maxItems",
        MAX_ITEMS_PER_RUN
    )

    try:
        requested_max = int(
            requested_max
        )

    except Exception:
        requested_max = (
            MAX_ITEMS_PER_RUN
        )

    max_items = max(
        1,
        min(
            requested_max,
            50
        )
    )

    company_id = clean_text(
        event.get(
            "companyId"
        )
    )

    source = clean_text(
        event.get(
            "source"
        )
    )

    force = normalize_boolean(
        event.get(
            "force",
            False
        )
    )

    logger.info(
        "Starting SocioWatch enrichment. "
        "companyId=%s source=%s maxItems=%s force=%s "
        "version=%s",
        company_id or "ALL",
        source or "ALL",
        max_items,
        force,
        ENRICHMENT_VERSION
    )

    # -----------------------------------------------------
    # Retrieve candidates
    # -----------------------------------------------------

    try:

        mentions = (
            get_enrichment_candidates(
                max_items=max_items,
                company_id=company_id,
                source=source,
                force=force
            )
        )

    except Exception:

        logger.exception(
            "Unable to retrieve enrichment candidates."
        )

        return build_response(
            500,
            {
                "message":
                    "Unable to retrieve mentions."
            }
        )

    processed = 0
    enriched = 0
    failed = 0
    skipped = 0

    relevant = 0
    irrelevant = 0

    high_priority = 0
    medium_priority = 0
    low_priority = 0

    summaries_created = 0
    changed_company_ids = set()

    for mention in mentions:

        processed += 1

        # -------------------------------------------------
        # Source licensing / AI processing permission
        #
        # Webz forum records can explicitly allow or deny
        # AI processing through AIAllow. Existing non-Webz
        # mentions do not have this field and remain allowed.
        # -------------------------------------------------

        if not is_ai_processing_allowed(
            mention
        ):

            skipped += 1

            try:

                mark_skipped_mention(
                    mention,
                    "AI processing not allowed by source."
                )

            except Exception:

                logger.exception(
                    "Unable to mark AI-disallowed mention skipped."
                )

            continue

        if not has_useful_content(
            mention
        ):

            skipped += 1

            try:

                mark_skipped_mention(
                    mention,
                    "No useful title or content."
                )

            except Exception:

                logger.exception(
                    "Unable to mark mention skipped."
                )

            continue

        try:

            enrichment = enrich_mention(
                mention
            )

            enrichment = preserve_connected_account_relevance(
                mention,
                enrichment
            )

            update_mention(
                mention,
                enrichment
            )

            enriched += 1

            mention_company_id = clean_text(
                mention.get(
                    "CompanyId"
                )
            )

            if mention_company_id:
                changed_company_ids.add(
                    mention_company_id
                )

            if enrichment[
                "IsRelevant"
            ]:

                relevant += 1

            else:

                irrelevant += 1

            priority = enrichment[
                "Priority"
            ]

            if priority == "high":

                high_priority += 1

            elif priority == "medium":

                medium_priority += 1

            else:

                low_priority += 1

            if enrichment[
                "AISummary"
            ]:

                summaries_created += 1

        except Exception:

            failed += 1

            logger.exception(
                "Enrichment failed for mention: %s",
                mention.get(
                    "MentionId",
                    "UNKNOWN"
                )
            )
    
    # ---------------------------------------------------------
    # Refresh Executive Summaries
    # ---------------------------------------------------------

    for changed_company_id in changed_company_ids:

        try:

            trigger_executive_summary(
                changed_company_id
            )

        except Exception:

            # Do not fail mention enrichment just because
            # executive summary refresh failed.
            logger.exception(
                "Unable to trigger executive summary. "
                "CompanyId=%s",
                changed_company_id
            )

    return build_response(
        200,
        {
            "message":
                "Mention enrichment completed.",

            "companyId":
                company_id or "ALL",

            "source":
                source or "ALL",

            "force":
                force,

            "mentionsSelected":
                len(mentions),

            "mentionsProcessed":
                processed,

            "mentionsEnriched":
                enriched,

            "mentionsRelevant":
                relevant,

            "mentionsIrrelevant":
                irrelevant,

            "mentionsFailed":
                failed,

            "mentionsSkipped":
                skipped,

            "summariesCreated":
                summaries_created,

            "highPriority":
                high_priority,

            "mediumPriority":
                medium_priority,

            "lowPriority":
                low_priority,

            "relevanceRules":
                list(
                    ALLOWED_RELEVANCE_RULES
                ),

            "enrichmentVersion":
                ENRICHMENT_VERSION,

            "modelId":
                BEDROCK_MODEL_ID
        }
    )


# ---------------------------------------------------------
# Read Enrichment Candidates
# ---------------------------------------------------------

def get_enrichment_candidates(
    max_items,
    company_id="",
    source="",
    force=False
):

    mentions = []

    scan_args = {}

    # -----------------------------------------------------
    # FORCE MODE
    #
    # Upgrade company mentions that have not yet
    # received the current enrichment version.
    #
    # AI will determine relevance during enrichment.
    # -----------------------------------------------------

    if force:

        filter_expression = (
            Attr(
                "AIEnrichmentVersion"
            ).not_exists()
            |
            Attr(
                "AIEnrichmentVersion"
            ).ne(
                ENRICHMENT_VERSION
            )
        )

    # -----------------------------------------------------
    # NORMAL SCHEDULED MODE
    #
    # Only new collector-approved mentions.
    # -----------------------------------------------------

    else:

        # Existing collectors use RelevanceRule.
        #
        # Webz uses its own source-level AI permission.
        # AI-allowed Webz mentions can be enriched even
        # though they do not use RelevanceRule.
        collector_approved = (
            Attr(
                "RelevanceRule"
            ).eq(
                "COMPANY_AND_KEYWORD"
            )
            |
            Attr(
                "RelevanceRule"
            ).eq(
                "COMPANY_IDENTITY"
            )
        )

        webz_ai_allowed = (
            Attr(
                "Source"
            ).eq(
                "webz"
            )
            &
            Attr(
                "AIAllow"
            ).eq(
                True
            )
        )

        google_reviews_ai_allowed = (
            Attr(
                "Source"
            ).eq(
                "GOOGLE_REVIEWS"
            )
        )

        filter_expression = (
            (
                collector_approved
                |
                webz_ai_allowed
                |
                google_reviews_ai_allowed
            )
            &
            Attr(
                "AIEnrichedAt"
            ).not_exists()
        )

    # -----------------------------------------------------
    # AI Processing Permission
    #
    # Existing mentions normally do not have AIAllow.
    # Treat a missing field as allowed.
    #
    # If a source explicitly stores AIAllow=False,
    # never send that mention to Bedrock — even in
    # force mode.
    # -----------------------------------------------------

    filter_expression = (
        filter_expression
        &
        (
            Attr(
                "UserMarkedIrrelevant"
            ).not_exists()
            |
            Attr(
                "UserMarkedIrrelevant"
            ).eq(
                False
            )
        )
        &
        (
            Attr(
                "AIAllow"
            ).not_exists()
            |
            Attr(
                "AIAllow"
            ).eq(
                True
            )
        )
        &
        (
            Attr(
                "AIProcessingAllowed"
            ).not_exists()
            |
            Attr(
                "AIProcessingAllowed"
            ).eq(
                True
            )
        )
    )

    # -----------------------------------------------------
    # Company Filter
    # -----------------------------------------------------

    if company_id:

        filter_expression = (
            filter_expression
            &
            Attr(
                "CompanyId"
            ).eq(
                company_id
            )
        )

    if source:

        filter_expression = (
            filter_expression
            &
            Attr(
                "Source"
            ).eq(
                source
            )
        )

    scan_args[
        "FilterExpression"
    ] = filter_expression

    while len(
        mentions
    ) < max_items:

        response = mentions_table.scan(
            **scan_args
        )

        for item in response.get(
            "Items",
            []
        ):

            mentions.append(
                item
            )

            if (
                len(mentions)
                >= max_items
            ):
                break

        last_key = response.get(
            "LastEvaluatedKey"
        )

        if (
            not last_key
            or len(mentions)
            >= max_items
        ):
            break

        scan_args[
            "ExclusiveStartKey"
        ] = last_key

    return mentions

# ---------------------------------------------------------
# Bedrock Enrichment
# ---------------------------------------------------------

def enrich_mention(
    mention
):

    if is_rating_only_google_review(
        mention
    ):

        return build_rating_only_enrichment(
            mention
        )

    prompt = build_prompt(
        mention
    )

    response = bedrock.converse(
        modelId=BEDROCK_MODEL_ID,

        system=[
            {
                "text": (
                    "You are the reputation intelligence "
                    "analyst for SocioWatch. "
                    "Your audience is a company executive, "
                    "marketing leader, customer experience "
                    "leader, or communications team. "
                    "Your job is not to rewrite headlines. "
                    "Explain what happened and why it matters "
                    "to the target company. "
                    "Use only supplied information. "
                    "Never invent facts, impact, motives, "
                    "customer reactions, or consequences. "
                    "Return valid JSON only."
                )
            }
        ],

        messages=[
            {
                "role":
                    "user",

                "content": [
                    {
                        "text":
                            prompt
                    }
                ]
            }
        ],

        inferenceConfig={
            "maxTokens":
                MAX_OUTPUT_TOKENS,

            "temperature":
                0
        }
    )

    response_text = (
        get_response_text(
            response
        )
    )

    parsed = parse_json_response(
        response_text
    )

    return normalize_enrichment(
        parsed
    )


def is_rating_only_google_review(
    mention
):

    return (
        clean_text(
            mention.get(
                "Source"
            )
        ).upper() == "GOOGLE_REVIEWS"
        and not clean_text(
            mention.get(
                "Content"
            )
        )
        and mention.get(
            "Rating"
        ) is not None
    )


def build_rating_only_enrichment(
    mention
):

    try:
        rating = float(
            mention.get(
                "Rating"
            )
        )
    except (TypeError, ValueError):
        rating = 0

    try:
        rating_max = float(
            mention.get(
                "RatingMax",
                5
            )
        )
    except (TypeError, ValueError):
        rating_max = 5

    rating_label = (
        str(int(rating))
        if rating.is_integer()
        else str(rating)
    )
    rating_max_label = (
        str(int(rating_max))
        if rating_max.is_integer()
        else str(rating_max)
    )

    if rating >= 4:
        sentiment = "positive"
        reputation_risk = "low"
        priority = "low"
        priority_reason = (
            "Positive rating with no written complaint or follow-up details."
        )
        action_required = False
        positive_aspects = [f"{rating_label}-star rating"]
        negative_aspects = []
        signal = "positive"
    elif rating <= 2:
        sentiment = "negative"
        reputation_risk = "medium"
        priority = "medium"
        priority_reason = (
            "Low rating without written details may warrant monitoring or follow-up."
        )
        action_required = True
        positive_aspects = []
        negative_aspects = [f"{rating_label}-star rating"]
        signal = "negative"
    else:
        sentiment = "neutral"
        reputation_risk = "low"
        priority = "low"
        priority_reason = (
            "Rating-only review provides no written details requiring action."
        )
        action_required = False
        positive_aspects = []
        negative_aspects = []
        signal = "neutral"

    return normalize_enrichment({
        "isRelevant": True,
        "relevanceScore": 100,
        "relevanceReason": (
            "Review belongs to the resolved Google Business Profile "
            "for the monitored company."
        ),
        "sentiment": sentiment,
        "mentionType": "review",
        "opinionDetected": True,
        "topics": ["Customer rating"],
        "positiveAspects": positive_aspects,
        "negativeAspects": negative_aspects,
        "reputationRisk": reputation_risk,
        "priority": priority,
        "priorityReason": priority_reason,
        "actionRequired": action_required,
        "summary": (
            f"A customer left a {rating_label} out of {rating_max_label} "
            "star Google review with no written comment. "
            f"This is a {signal} rating signal, but no specific experience "
            "details were provided."
        ),
        "keyTakeaway": (
            f"{rating_label}-star rating submitted without a written comment."
        )
    })


# ---------------------------------------------------------
# Prompt
# ---------------------------------------------------------

def build_prompt(
    mention
):

    title = clean_text(
        mention.get(
            "Title"
        )
    )

    content = clean_text(
        mention.get(
            "Content"
        )
    )

    company_name = clean_text(
        mention.get(
            "CompanyName"
        )
    )

    source_domain = clean_text(
        mention.get(
            "SourceDomain"
        )
    )

    source_type = clean_text(
        mention.get(
            "SourceType"
        )
    )

    url = clean_text(
        mention.get(
            "Url"
        )
    )

    relevance_rule = clean_text(
        mention.get(
            "RelevanceRule"
        )
    )

    source = clean_text(
        mention.get(
            "Source"
        )
    )

    business_name = clean_text(
        mention.get(
            "BusinessName"
        )
    )

    business_location = clean_text(
        mention.get(
            "BusinessLocation"
        )
    )

    owner_response = clean_text(
        mention.get(
            "OwnerResponse"
        )
    )

    rating = mention.get(
        "Rating"
    )

    rating_max = mention.get(
        "RatingMax",
        5
    )

    rating_text = (
        f"{rating} out of {rating_max}"
        if rating is not None
        else "Not provided"
    )

    matched_keywords = normalize_string_list(
        mention.get(
            "MatchedKeywords",
            []
        ),
        max_items=10
    )

    matched_identity_terms = normalize_string_list(
        mention.get(
            "MatchedIdentityTerms",
            []
        ),
        max_items=10
    )

    keyword_text = ", ".join(
        matched_keywords
    )

    identity_text = ", ".join(
        matched_identity_terms
    )

    content = content[
        :MAX_INPUT_CHARACTERS
    ]

    return f"""
TARGET COMPANY:
{company_name or 'Unknown'}

MATCHED COMPANY IDENTITY TERMS:
{identity_text or 'Not provided'}

MATCHED MONITORING KEYWORDS:
{keyword_text or 'None provided'}

COLLECTOR RELEVANCE RULE:
{relevance_rule or 'Legacy / Unknown'}

SOURCE DOMAIN:
{source_domain or 'Unknown'}

SOURCE TYPE:
{source_type or 'Unknown'}

SOURCE:
{source or 'Unknown'}

GOOGLE REVIEW BUSINESS:
{business_name or 'Not applicable'}

GOOGLE REVIEW LOCATION:
{business_location or 'Not applicable'}

GOOGLE STAR RATING:
{rating_text}

BUSINESS OWNER RESPONSE:
{owner_response or 'None'}

URL:
{url or 'Unknown'}

HEADLINE:
{title or 'None'}

ARTICLE / MENTION CONTENT:
{content or 'None'}


TASK:

Determine whether this content genuinely concerns the
target company.

Then explain the mention in a way that helps a business
leader quickly understand:

1. What happened?
2. Why does it matter, if at all?


Return exactly one JSON object:

{{
  "isRelevant": true,
  "relevanceScore": 0,
  "relevanceReason": "Short explanation.",
  "sentiment": "positive | negative | neutral | mixed",
  "mentionType": "complaint | praise | review | discussion | question | news | other",
  "opinionDetected": true,
  "topics": ["topic"],
  "positiveAspects": ["short phrase"],
  "negativeAspects": ["short phrase"],
  "reputationRisk": "low | medium | high",
  "priority": "low | medium | high",
  "priorityReason": "Short explanation.",
  "actionRequired": false,
  "summary": "Maximum two concise sentences.",
  "keyTakeaway": "One short business takeaway."
}}


RELEVANCE RULES:

- relevanceScore must be an integer from 0 to 100.

- 80-100:
  clearly about the target company.

- 60-79:
  likely about the company but some ambiguity exists.

- 0-59:
  insufficient evidence or likely unrelated.

- isRelevant should normally be true only when
  relevanceScore >= 60.

- A keyword alone is not sufficient proof.

- If clearly unrelated:
  isRelevant=false,
  priority="low",
  reputationRisk="low",
  actionRequired=false.


SENTIMENT RULES:

- positive:
  clearly favorable language, praise, positive customer
  experience, recognition, or positive business signal.

- negative:
  clearly unfavorable language, complaint, criticism,
  failure, negative experience, or reputation concern.

- neutral:
  primarily factual reporting without meaningful
  positive or negative tone.

- mixed:
  meaningful positive and negative signals both exist.


PRIORITY RULES:

HIGH:
- major customer/service failure
- serious complaint
- safety issue
- fraud allegation
- legal/reputation crisis
- major damaging media coverage
- issue requiring timely investigation or escalation

MEDIUM:
- meaningful complaint or criticism
- mixed customer experience
- concerning review
- issue worth monitoring or responding to
- moderate reputation risk

LOW:
- routine factual news
- routine financial reporting
- normal executive or insider stock transactions
- ordinary company announcements
- positive coverage with no action required
- low-impact discussion


ACTION REQUIRED:

Set actionRequired=true only when a company representative
should reasonably:

- investigate
- respond
- escalate
- correct misinformation
- contact a customer
- monitor the issue closely

Do not make every negative mention actionable.


SUMMARY RULES:

The summary is extremely important.

- Maximum 2 short sentences.

- Do NOT simply repeat or lightly rewrite the headline.

- Sentence 1:
  Explain what actually happened.

- Sentence 2:
  Explain why it matters to the company's reputation,
  customers, leadership, or business — but ONLY when the
  supplied content supports such an implication.

- If the story appears routine or low-impact, explicitly
  say that it appears to have limited direct reputation
  impact.

- For routine insider stock sales, financial filings,
  or ordinary market reporting:
  explain the event briefly and state that it appears
  to be routine financial/market coverage unless the
  supplied content indicates otherwise.

- For customer complaints:
  identify the actual customer problem and explain
  what trust/service issue may require attention.

- For positive customer experiences:
  identify specifically what the customer values.

- For factual company news:
  explain the development and whether any meaningful
  reputation implication is evident.

- Do not speculate.

- Do not invent customer sentiment.

- Do not claim something affects reputation unless the
  supplied information reasonably supports that conclusion.

- Avoid generic phrases such as:
  "This article discusses..."
  "This mention is about..."
  "The headline states..."

- Write naturally for an executive dashboard.


KEY TAKEAWAY RULES:

- Maximum 15 words.

- Make it useful when scanning many mentions.

Examples:

"Routine insider stock transaction; limited reputation impact."

"Customer service complaint may require follow-up."

"Positive customer review highlights strong installation experience."

"Product announcement with no immediate reputation concern."

Do NOT simply copy the headline.


OTHER RULES:

- A GOOGLE_REVIEWS mention is tied to a previously resolved
  Google Business Profile for the target company. Do not mark
  it irrelevant merely because monitoring keywords are absent.

- For a Google review, always use mentionType="review".

- Preserve the star rating as a separate factual signal.
  When review text exists, determine sentiment from the full
  language and do not rely on the rating alone.

- A star-only Google review is still a valid mention. When no
  written content exists, classify it cautiously from the rating:
  1-2 negative, 3 neutral, and 4-5 positive. State clearly in
  the summary that the reviewer left no written comment.

- An owner response is company-authored context, not part of
  the customer's opinion. Do not attribute it to the reviewer.

- Straight factual news should normally use:
  mentionType="news"
  opinionDetected=false

- Keep topics to at most 5.

- Keep positiveAspects to at most 5.

- Keep negativeAspects to at most 5.

- Use empty arrays when unsupported.

- reputationRisk applies only to this specific mention.

- Return JSON only.
""".strip()


# ---------------------------------------------------------
# Bedrock Response
# ---------------------------------------------------------

def get_response_text(
    response
):

    content_blocks = (
        response
        .get(
            "output",
            {}
        )
        .get(
            "message",
            {}
        )
        .get(
            "content",
            []
        )
    )

    text_parts = []

    for block in content_blocks:

        text = clean_text(
            block.get(
                "text"
            )
        )

        if text:

            text_parts.append(
                text
            )

    response_text = "\n".join(
        text_parts
    ).strip()

    if not response_text:

        raise ValueError(
            "Bedrock returned no text response."
        )

    return response_text


def parse_json_response(
    response_text
):

    value = response_text.strip()

    value = re.sub(
        r"^```(?:json)?\s*",
        "",
        value,
        flags=re.IGNORECASE
    )

    value = re.sub(
        r"\s*```$",
        "",
        value
    )

    try:

        return json.loads(
            value
        )

    except json.JSONDecodeError:

        start = value.find(
            "{"
        )

        end = value.rfind(
            "}"
        )

        if (
            start >= 0
            and end > start
        ):

            return json.loads(
                value[
                    start:end + 1
                ]
            )

        raise


# ---------------------------------------------------------
# Normalize AI Output
# ---------------------------------------------------------

def normalize_enrichment(
    value
):

    if not isinstance(
        value,
        dict
    ):

        raise ValueError(
            "Bedrock response was not a JSON object."
        )

    relevance_score = normalize_score(
        value.get(
            "relevanceScore"
        )
    )

    is_relevant = normalize_boolean(
        value.get(
            "isRelevant"
        )
    )

    if relevance_score < 60:

        is_relevant = False

    relevance_reason = clean_text(
        value.get(
            "relevanceReason"
        )
    )[:500]

    sentiment = normalize_enum(
        value.get(
            "sentiment"
        ),
        {
            "positive",
            "negative",
            "neutral",
            "mixed"
        },
        "neutral"
    )

    mention_type = normalize_enum(
        value.get(
            "mentionType"
        ),
        {
            "complaint",
            "praise",
            "review",
            "discussion",
            "question",
            "news",
            "other"
        },
        "other"
    )

    reputation_risk = normalize_enum(
        value.get(
            "reputationRisk"
        ),
        {
            "low",
            "medium",
            "high"
        },
        "low"
    )

    priority = normalize_enum(
        value.get(
            "priority"
        ),
        {
            "low",
            "medium",
            "high"
        },
        "low"
    )

    priority_reason = clean_text(
        value.get(
            "priorityReason"
        )
    )[:500]

    action_required = normalize_boolean(
        value.get(
            "actionRequired"
        )
    )

    opinion_detected = normalize_boolean(
        value.get(
            "opinionDetected"
        )
    )

    topics = normalize_string_list(
        value.get(
            "topics"
        ),
        max_items=5
    )

    positive_aspects = normalize_string_list(
        value.get(
            "positiveAspects"
        ),
        max_items=5
    )

    negative_aspects = normalize_string_list(
        value.get(
            "negativeAspects"
        ),
        max_items=5
    )

    summary = clean_text(
        value.get(
            "summary"
        )
    )[:1200]

    key_takeaway = clean_text(
        value.get(
            "keyTakeaway"
        )
    )[:300]

    # -----------------------------------------------------
    # Irrelevant mentions should never become alerts
    # -----------------------------------------------------

    if not is_relevant:

        priority = "low"

        reputation_risk = "low"

        action_required = False

    return {
        "IsRelevant":
            is_relevant,

        "RelevanceScore":
            relevance_score,

        "RelevanceReason":
            relevance_reason,

        "Sentiment":
            sentiment,

        "MentionType":
            mention_type,

        "OpinionDetected":
            opinion_detected,

        "Topics":
            topics,

        "PositiveAspects":
            positive_aspects,

        "NegativeAspects":
            negative_aspects,

        "ReputationRisk":
            reputation_risk,

        "Priority":
            priority,

        "PriorityReason":
            priority_reason,

        "ActionRequired":
            action_required,

        "AISummary":
            summary,

        "KeyTakeaway":
            key_takeaway
    }


# ---------------------------------------------------------
# Update DynamoDB Mention
# ---------------------------------------------------------

def update_mention(
    mention,
    enrichment
):

    company_month = mention.get(
        "CompanyMonth"
    )

    mention_key = mention.get(
        "MentionKey"
    )

    if (
        not company_month
        or not mention_key
    ):

        raise ValueError(
            "Mention is missing primary key values."
        )

    enriched_at = utc_now_iso()

    mentions_table.update_item(

        Key={
            "CompanyMonth":
                company_month,

            "MentionKey":
                mention_key
        },

        UpdateExpression=(
            "SET "
            "#isRelevant = :isRelevant, "
            "#relevanceScore = :relevanceScore, "
            "#relevanceReason = :relevanceReason, "
            "#sentiment = :sentiment, "
            "#mentionType = :mentionType, "
            "#opinionDetected = :opinionDetected, "
            "#topics = :topics, "
            "#positiveAspects = :positiveAspects, "
            "#negativeAspects = :negativeAspects, "
            "#reputationRisk = :reputationRisk, "
            "#priority = :priority, "
            "#priorityReason = :priorityReason, "
            "#actionRequired = :actionRequired, "
            "#aiSummary = :aiSummary, "
            "#keyTakeaway = :keyTakeaway, "
            "#aiEnrichmentStatus = :status, "
            "#aiEnrichedAt = :enrichedAt, "
            "#aiModelId = :modelId, "
            "#aiEnrichmentVersion = :version, "
            "#collectionStatus = :collectionStatus "
            "REMOVE #enrichmentError, #skipReason"
        ),

        ExpressionAttributeNames={
            "#isRelevant":
                "IsRelevant",

            "#relevanceScore":
                "RelevanceScore",

            "#relevanceReason":
                "RelevanceReason",

            "#sentiment":
                "Sentiment",

            "#mentionType":
                "MentionType",

            "#opinionDetected":
                "OpinionDetected",

            "#topics":
                "Topics",

            "#positiveAspects":
                "PositiveAspects",

            "#negativeAspects":
                "NegativeAspects",

            "#reputationRisk":
                "ReputationRisk",

            "#priority":
                "Priority",

            "#priorityReason":
                "PriorityReason",

            "#actionRequired":
                "ActionRequired",

            "#aiSummary":
                "AISummary",

            "#keyTakeaway":
                "KeyTakeaway",

            "#aiEnrichmentStatus":
                "AIEnrichmentStatus",

            "#aiEnrichedAt":
                "AIEnrichedAt",

            "#aiModelId":
                "AIModelId",

            "#aiEnrichmentVersion":
                "AIEnrichmentVersion",

            "#collectionStatus":
                "EnrichmentStatus",

            "#enrichmentError":
                "AIEnrichmentError",

            "#skipReason":
                "AIEnrichmentSkipReason"
        },

        ExpressionAttributeValues={
            ":isRelevant":
                enrichment[
                    "IsRelevant"
                ],

            ":relevanceScore":
                enrichment[
                    "RelevanceScore"
                ],

            ":relevanceReason":
                enrichment[
                    "RelevanceReason"
                ],

            ":sentiment":
                enrichment[
                    "Sentiment"
                ],

            ":mentionType":
                enrichment[
                    "MentionType"
                ],

            ":opinionDetected":
                enrichment[
                    "OpinionDetected"
                ],

            ":topics":
                enrichment[
                    "Topics"
                ],

            ":positiveAspects":
                enrichment[
                    "PositiveAspects"
                ],

            ":negativeAspects":
                enrichment[
                    "NegativeAspects"
                ],

            ":reputationRisk":
                enrichment[
                    "ReputationRisk"
                ],

            ":priority":
                enrichment[
                    "Priority"
                ],

            ":priorityReason":
                enrichment[
                    "PriorityReason"
                ],

            ":actionRequired":
                enrichment[
                    "ActionRequired"
                ],

            ":aiSummary":
                enrichment[
                    "AISummary"
                ],

            ":keyTakeaway":
                enrichment[
                    "KeyTakeaway"
                ],

            ":status":
                "completed",

            ":enrichedAt":
                enriched_at,

            ":modelId":
                BEDROCK_MODEL_ID,

            ":version":
                ENRICHMENT_VERSION,

            ":collectionStatus":
                "COMPLETED"
        }
    )


# ---------------------------------------------------------
# Mark Skipped Mention
# ---------------------------------------------------------

def mark_skipped_mention(
    mention,
    reason
):

    company_month = mention.get(
        "CompanyMonth"
    )

    mention_key = mention.get(
        "MentionKey"
    )

    if (
        not company_month
        or not mention_key
    ):
        return

    mentions_table.update_item(

        Key={
            "CompanyMonth":
                company_month,

            "MentionKey":
                mention_key
        },

        UpdateExpression=(
            "SET "
            "#status = :status, "
            "#enrichedAt = :enrichedAt, "
            "#version = :version, "
            "#reason = :reason, "
            "#collectionStatus = :collectionStatus"
        ),

        ExpressionAttributeNames={
            "#status":
                "AIEnrichmentStatus",

            "#enrichedAt":
                "AIEnrichedAt",

            "#version":
                "AIEnrichmentVersion",

            "#reason":
                "AIEnrichmentSkipReason",

            "#collectionStatus":
                "EnrichmentStatus"
        },

        ExpressionAttributeValues={
            ":status":
                "skipped",

            ":enrichedAt":
                utc_now_iso(),

            ":version":
                ENRICHMENT_VERSION,

            ":reason":
                clean_text(
                    reason
                )[:500],

            ":collectionStatus":
                "SKIPPED"
        }
    )


# ---------------------------------------------------------
# Helpers
# ---------------------------------------------------------

def is_ai_processing_allowed(
    mention
):
    """
    Existing collectors do not store AIAllow, so a missing
    field remains allowed.

    When a source explicitly sets AIAllow=False, the mention
    may still be stored/displayed but must not be sent to AI.
    """

    if (
        "AIProcessingAllowed" in mention
        and not normalize_boolean(
            mention.get(
                "AIProcessingAllowed"
            )
        )
    ):
        return False

    if "AIAllow" not in mention:
        return True

    return normalize_boolean(
        mention.get(
            "AIAllow"
        )
    )


def has_useful_content(
    mention
):

    title = clean_text(
        mention.get(
            "Title"
        )
    )

    content = clean_text(
        mention.get(
            "Content"
        )
    )

    is_rating_only_review = (
        clean_text(
            mention.get(
                "Source"
            )
        ).upper() == "GOOGLE_REVIEWS"
        and mention.get(
            "Rating"
        ) is not None
    )

    return bool(
        title
        or content
        or is_rating_only_review
    )


def normalize_score(
    value
):

    try:

        score = int(
            value
        )

    except Exception:

        score = 0

    return max(
        0,
        min(
            score,
            100
        )
    )


def normalize_enum(
    value,
    allowed,
    default
):

    value = clean_text(
        value
    ).lower()

    if value in allowed:

        return value

    return default


def normalize_boolean(
    value
):

    if isinstance(
        value,
        bool
    ):

        return value

    if isinstance(
        value,
        str
    ):

        return (
            value
            .strip()
            .lower()
            in {
                "true",
                "yes",
                "1"
            }
        )

    if isinstance(
        value,
        int
    ):

        return value == 1

    return False


def normalize_string_list(
    value,
    max_items=5
):

    if not isinstance(
        value,
        list
    ):

        return []

    cleaned = []

    seen = set()

    for item in value:

        item = clean_text(
            item
        )

        if not item:
            continue

        normalized = (
            item.lower()
        )

        if normalized in seen:
            continue

        seen.add(
            normalized
        )

        cleaned.append(
            item[:200]
        )

        if len(
            cleaned
        ) >= max_items:
            break

    return cleaned


def normalize_event(
    event
):

    if not isinstance(
        event,
        dict
    ):

        return {}

    body = event.get(
        "body"
    )

    if isinstance(
        body,
        str
    ):

        try:

            body_json = json.loads(
                body
            )

            if isinstance(
                body_json,
                dict
            ):

                merged = dict(
                    event
                )

                merged.update(
                    body_json
                )

                return merged

        except json.JSONDecodeError:
            pass

    return event


def clean_text(
    value
):

    if not isinstance(
        value,
        str
    ):

        return ""

    return value.strip()


def utc_now_iso():

    return (
        datetime.now(
            timezone.utc
        )
        .isoformat()
        .replace(
            "+00:00",
            "Z"
        )
    )


def build_response(
    status_code,
    body
):

    return {
        "statusCode":
            status_code,

        "headers": {
            "Content-Type":
                "application/json"
        },

        "body":
            json.dumps(
                body
            )
    }


# ---------------------------------------------------------
# Executive Summary
# ---------------------------------------------------------

def trigger_executive_summary(
    company_id
):

    if not EXECUTIVE_SUMMARY_FUNCTION:
        return

    logger.info(
        "Triggering executive summary refresh. "
        "CompanyId=%s",
        company_id
    )

    lambda_client.invoke(
        FunctionName=
            EXECUTIVE_SUMMARY_FUNCTION,

        InvocationType=
            "Event",

        Payload=json.dumps(
            {
                "companyId":
                    company_id,

                "days":
                    30
            }
        ).encode(
            "utf-8"
        )
    )
