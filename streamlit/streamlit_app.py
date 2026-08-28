import json

import altair as alt
import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(
    page_title="Customer 360 & Next Best Action",
    page_icon="🏦",
    layout="wide",
    initial_sidebar_state="expanded",
)

session = get_active_session()

DB = "INSURANCE_360"
AGENT_FQN = f"{DB}.AI.CUSTOMER_360_AGENT"

TAB_PORTFOLIO = "🏠  Portfolio"
TAB_360 = "📋  Customer 360"
TAB_CHAT = "💬  Ask & Next Best Action"

# ---------------------------------------------------------------------------
# Styling
# ---------------------------------------------------------------------------
PRIMARY = "#29B5E8"
DARK = "#11567F"
ACCENT = "#7C5CFC"

st.markdown(
    f"""
    <style>
    .app-header {{
        background: linear-gradient(135deg, {DARK} 0%, {PRIMARY} 100%);
        padding: 1.4rem 1.6rem;
        border-radius: 14px;
        color: white;
        margin-bottom: 1.2rem;
        box-shadow: 0 4px 18px rgba(17,86,127,0.25);
    }}
    .app-header h1 {{
        color: white; margin: 0; font-size: 1.6rem;
    }}
    .app-header p {{
        color: #eaf7fd; margin: 0.25rem 0 0 0; font-size: 0.95rem;
    }}
    .customer-card {{
        border: 1px solid #e3e8ee;
        border-radius: 12px;
        padding: 1rem 1.2rem;
        background: #ffffff;
        margin-bottom: 0.8rem;
    }}
    .metric-card {{
        border: 1px solid #e3e8ee;
        border-left: 4px solid {PRIMARY};
        border-radius: 10px;
        padding: 0.7rem 1rem;
        background: #fafcff;
        text-align: left;
        transition: box-shadow 0.15s ease;
    }}
    .metric-card:hover {{ box-shadow: 0 2px 10px rgba(17,86,127,0.12); }}
    .metric-card .metric-label {{
        font-size: 0.78rem; color: #5a6b7a; text-transform: uppercase; letter-spacing: 0.03em;
    }}
    .metric-card .metric-value {{
        font-size: 1.5rem; font-weight: 700; color: {DARK}; margin-top: 0.1rem;
    }}
    .metric-card .metric-delta {{
        font-size: 0.76rem; margin-top: 0.15rem; font-weight: 600;
    }}
    .metric-card.warn {{ border-left-color: #e0782f; }}
    .metric-card.danger {{ border-left-color: #c53030; }}
    .metric-card.good {{ border-left-color: #1a7f37; }}
    .badge {{
        display: inline-block; padding: 3px 12px; border-radius: 999px;
        font-size: 0.78rem; font-weight: 600; white-space: nowrap;
    }}
    .badge-low {{ background:#e6f4ea; color:#1a7f37; }}
    .badge-medium {{ background:#fff4e0; color:#b65c00; }}
    .badge-high {{ background:#fdecea; color:#c53030; }}
    .badge-neutral {{ background:#eef1f4; color:#4a5568; }}
    .badge-positive {{ background:#e6f4ea; color:#1a7f37; }}
    .badge-negative {{ background:#fdecea; color:#c53030; }}
    .badge-mixed {{ background:#fff4e0; color:#b65c00; }}
    .section-title {{
        font-size: 1.05rem; font-weight: 700; color: {DARK};
        margin: 1.1rem 0 0.5rem 0; display:flex; align-items:center; gap:0.4rem;
    }}
    .interaction-card {{
        border: 1px solid #e3e8ee; border-radius: 10px; padding: 0.7rem 1rem;
        margin-bottom: 0.5rem; background: #ffffff;
    }}
    .chip-btn button {{
        border-radius: 999px !important;
    }}
    .nba-card {{
        border-radius: 14px;
        padding: 1.1rem 1.3rem;
        background: linear-gradient(135deg, #f4f0ff 0%, #eef8fd 100%);
        border: 1px solid #e1d9ff;
        margin-bottom: 1rem;
    }}
    .nba-card .nba-label {{
        font-size: 0.75rem; font-weight: 700; text-transform: uppercase;
        letter-spacing: 0.04em; color: {ACCENT}; margin-bottom: 0.3rem;
    }}
    .nba-card .nba-action {{
        font-size: 1.08rem; font-weight: 700; color: {DARK}; margin-bottom: 0.35rem;
    }}
    .nba-card .nba-rationale {{
        font-size: 0.9rem; color: #47556b;
    }}
    .attn-row {{
        border: 1px solid #e3e8ee; border-radius: 10px; padding: 0.6rem 0.9rem;
        margin-bottom: 0.5rem; background: #ffffff; display:flex; align-items:center;
        justify-content: space-between; gap: 0.6rem;
    }}
    .demo-chip button {{
        border-radius: 999px !important; border-color: {ACCENT} !important; color: {ACCENT} !important;
    }}
    </style>
    """,
    unsafe_allow_html=True,
)

RISK_BADGE = {
    "Low Churn Risk": ("badge-low", "🟢 Low churn risk"),
    "Medium Churn Risk": ("badge-medium", "🟠 Medium churn risk"),
    "High Churn Risk": ("badge-high", "🔴 High churn risk"),
}
SENTIMENT_BADGE = {
    "positive": ("badge-positive", "🙂 Positive"),
    "neutral": ("badge-neutral", "😐 Neutral"),
    "negative": ("badge-negative", "🙁 Negative"),
    "mixed": ("badge-mixed", "😕 Mixed"),
}
CHANNEL_ICON = {"Phone Call": "📞", "Chat": "💬", "Email": "✉️"}
SENTIMENT_SCORE = {"positive": 1, "neutral": 0, "mixed": -0.5, "negative": -1}
RISK_COLOR = {"Low Churn Risk": "#1a7f37", "Medium Churn Risk": "#b65c00", "High Churn Risk": "#c53030"}


def badge_html(css_class, text):
    return f'<span class="badge {css_class}">{text}</span>'


def risk_badge_html(risk):
    css, text = RISK_BADGE.get(risk, ("badge-neutral", risk or "Unknown"))
    return badge_html(css, text)


def sentiment_badge_html(sentiment):
    css, text = SENTIMENT_BADGE.get(sentiment, ("badge-neutral", sentiment or "Unknown"))
    return badge_html(css, text)


def metric_card(label, value, variant="", delta=None):
    delta_html = f'<div class="metric-delta" style="color:{delta[1]}">{delta[0]}</div>' if delta else ""
    st.markdown(
        f"""
        <div class="metric-card {variant}">
            <div class="metric-label">{label}</div>
            <div class="metric-value">{value}</div>
            {delta_html}
        </div>
        """,
        unsafe_allow_html=True,
    )


# ---------------------------------------------------------------------------
# Data access
# ---------------------------------------------------------------------------
# Safety cap for the customer picker: at this app's target scale (hundreds to
# a few thousand customers) all of them comfortably fit in one selectbox with
# instant, client-side type-ahead — no server round-trip per keystroke needed.
# The cap just guards against an unbounded load if the table grows far beyond
# that; it is not meant to change the single-dropdown UX.
CUSTOMER_LIST_CAP = 5000


@st.cache_data(ttl=300)
def load_customers():
    return session.sql(
        f"""
        SELECT CUSTOMER_ID, FIRST_NAME, LAST_NAME, CUSTOMER_SEGMENT, STATE,
               CUSTOMER_SINCE, CHANNEL_ACQUIRED, CREDIT_SCORE_BAND
        FROM {DB}.RAW.CUSTOMERS
        ORDER BY CUSTOMER_ID
        LIMIT {CUSTOMER_LIST_CAP}
        """
    ).to_pandas()


@st.cache_data(ttl=120)
def load_customer_by_id(customer_id):
    return session.sql(
        f"""
        SELECT CUSTOMER_ID, FIRST_NAME, LAST_NAME, CUSTOMER_SEGMENT, STATE,
               CUSTOMER_SINCE, CHANNEL_ACQUIRED, CREDIT_SCORE_BAND
        FROM {DB}.RAW.CUSTOMERS
        WHERE CUSTOMER_ID = '{customer_id}'
        """
    ).to_pandas()


@st.cache_data(ttl=60)
def load_customer_metrics(customer_id):
    """Single-row lookup against the pre-aggregated rollup table instead of
    scanning/joining POLICIES, CLAIMS, and PAYMENTS on every page load."""
    return session.sql(
        f"""
        SELECT TOTAL_ANNUAL_PREMIUM, ACTIVE_POLICY_COUNT, CLAIM_COUNT,
               TOTAL_CLAIM_AMOUNT, MISSED_PAYMENT_COUNT,
               LATEST_CHURN_RISK, LATEST_SENTIMENT, LAST_INTERACTION_DATE,
               REVENUE_AT_RISK, PRIORITY_SCORE, NEXT_BEST_ACTION, NBA_RATIONALE
        FROM {DB}.CURATED.CUSTOMER_METRICS_SUMMARY
        WHERE CUSTOMER_ID = '{customer_id}'
        """
    ).to_pandas()


@st.cache_data(ttl=120)
def load_policies(customer_id):
    return session.sql(
        f"""
        SELECT POLICY_ID, LINE_OF_BUSINESS, POLICY_NUMBER, STATUS,
               EFFECTIVE_DATE, RENEWAL_DATE, ANNUAL_PREMIUM, COVERAGE_AMOUNT, DEDUCTIBLE
        FROM {DB}.RAW.POLICIES
        WHERE CUSTOMER_ID = '{customer_id}'
        ORDER BY EFFECTIVE_DATE DESC
        """
    ).to_pandas()


@st.cache_data(ttl=120)
def load_claims(customer_id):
    return session.sql(
        f"""
        SELECT CLAIM_ID, POLICY_ID, CLAIM_TYPE, CLAIM_DATE, CLAIM_AMOUNT, STATUS, RESOLUTION_DAYS
        FROM {DB}.RAW.CLAIMS
        WHERE CUSTOMER_ID = '{customer_id}'
        ORDER BY CLAIM_DATE DESC
        """
    ).to_pandas()


@st.cache_data(ttl=120)
def load_payments(customer_id):
    return session.sql(
        f"""
        SELECT PAYMENT_ID, POLICY_ID, DUE_DATE, PAID_DATE, AMOUNT, STATUS, PAYMENT_METHOD
        FROM {DB}.RAW.PAYMENTS
        WHERE CUSTOMER_ID = '{customer_id}'
        ORDER BY DUE_DATE DESC
        """
    ).to_pandas()


@st.cache_data(ttl=120)
def load_interactions(customer_id):
    return session.sql(
        f"""
        SELECT INTERACTION_ID, POLICY_ID, LINE_OF_BUSINESS, SCENARIO_TYPE, CHANNEL,
               INTERACTION_DATE, SENTIMENT_OVERALL, CHURN_RISK_LEVEL, PRIMARY_INTENT, TRANSCRIPT_TEXT
        FROM {DB}.CURATED.INTERACTIONS_ENRICHED
        WHERE CUSTOMER_ID = '{customer_id}'
        ORDER BY INTERACTION_DATE DESC
        """
    ).to_pandas()


@st.cache_data(ttl=300)
def load_portfolio_kpis():
    return session.sql(
        f"""
        SELECT
            COUNT(*) AS CUSTOMER_COUNT,
            SUM(TOTAL_ANNUAL_PREMIUM) AS TOTAL_BOOK_PREMIUM,
            AVG(TOTAL_ANNUAL_PREMIUM) AS AVG_PREMIUM,
            SUM(REVENUE_AT_RISK) AS TOTAL_REVENUE_AT_RISK,
            SUM(TOTAL_CLAIM_AMOUNT) AS TOTAL_CLAIMS_PAID,
            SUM(CASE WHEN LATEST_CHURN_RISK = 'High Churn Risk' THEN 1 ELSE 0 END) AS HIGH_RISK_COUNT
        FROM {DB}.CURATED.CUSTOMER_METRICS_SUMMARY
        """
    ).to_pandas()


@st.cache_data(ttl=300)
def load_churn_distribution():
    return session.sql(
        f"""
        SELECT COALESCE(LATEST_CHURN_RISK, 'Unknown') AS RISK, COUNT(*) AS CUSTOMERS
        FROM {DB}.CURATED.CUSTOMER_METRICS_SUMMARY
        GROUP BY 1
        """
    ).to_pandas()


@st.cache_data(ttl=300)
def load_segment_breakdown():
    return session.sql(
        f"""
        SELECT c.CUSTOMER_SEGMENT, COUNT(*) AS CUSTOMERS, SUM(m.TOTAL_ANNUAL_PREMIUM) AS PREMIUM
        FROM {DB}.RAW.CUSTOMERS c
        JOIN {DB}.CURATED.CUSTOMER_METRICS_SUMMARY m ON m.CUSTOMER_ID = c.CUSTOMER_ID
        GROUP BY 1
        ORDER BY PREMIUM DESC
        """
    ).to_pandas()


@st.cache_data(ttl=300)
def load_state_breakdown():
    return session.sql(
        f"""
        SELECT c.STATE, COUNT(*) AS CUSTOMERS, SUM(m.TOTAL_ANNUAL_PREMIUM) AS PREMIUM,
               SUM(m.REVENUE_AT_RISK) AS REVENUE_AT_RISK
        FROM {DB}.RAW.CUSTOMERS c
        JOIN {DB}.CURATED.CUSTOMER_METRICS_SUMMARY m ON m.CUSTOMER_ID = c.CUSTOMER_ID
        GROUP BY 1
        """
    ).to_pandas()


@st.cache_data(ttl=180)
def load_attention_list(limit=8):
    return session.sql(
        f"""
        SELECT c.CUSTOMER_ID, c.FIRST_NAME, c.LAST_NAME, c.CUSTOMER_SEGMENT,
               m.TOTAL_ANNUAL_PREMIUM, m.LATEST_CHURN_RISK, m.PRIORITY_SCORE,
               m.REVENUE_AT_RISK, m.NEXT_BEST_ACTION
        FROM {DB}.RAW.CUSTOMERS c
        JOIN {DB}.CURATED.CUSTOMER_METRICS_SUMMARY m ON m.CUSTOMER_ID = c.CUSTOMER_ID
        ORDER BY m.PRIORITY_SCORE DESC
        LIMIT {limit}
        """
    ).to_pandas()


@st.cache_data(ttl=300)
def load_demo_customers():
    return session.sql(
        f"""
        SELECT CUSTOMER_ID, FIRST_NAME, LAST_NAME, 'highest_risk' AS DEMO_TYPE FROM (
            SELECT c.CUSTOMER_ID, c.FIRST_NAME, c.LAST_NAME
            FROM {DB}.RAW.CUSTOMERS c JOIN {DB}.CURATED.CUSTOMER_METRICS_SUMMARY m ON m.CUSTOMER_ID = c.CUSTOMER_ID
            WHERE m.LATEST_CHURN_RISK = 'High Churn Risk' ORDER BY m.PRIORITY_SCORE DESC LIMIT 1
        )
        UNION ALL
        SELECT CUSTOMER_ID, FIRST_NAME, LAST_NAME, 'highest_value' AS DEMO_TYPE FROM (
            SELECT c.CUSTOMER_ID, c.FIRST_NAME, c.LAST_NAME
            FROM {DB}.RAW.CUSTOMERS c JOIN {DB}.CURATED.CUSTOMER_METRICS_SUMMARY m ON m.CUSTOMER_ID = c.CUSTOMER_ID
            ORDER BY m.TOTAL_ANNUAL_PREMIUM DESC LIMIT 1
        )
        UNION ALL
        SELECT CUSTOMER_ID, FIRST_NAME, LAST_NAME, 'largest_claim' AS DEMO_TYPE FROM (
            SELECT c.CUSTOMER_ID, c.FIRST_NAME, c.LAST_NAME
            FROM {DB}.RAW.CUSTOMERS c JOIN {DB}.CURATED.CUSTOMER_METRICS_SUMMARY m ON m.CUSTOMER_ID = c.CUSTOMER_ID
            ORDER BY m.TOTAL_CLAIM_AMOUNT DESC LIMIT 1
        )
        UNION ALL
        SELECT CUSTOMER_ID, FIRST_NAME, LAST_NAME, 'happiest' AS DEMO_TYPE FROM (
            SELECT c.CUSTOMER_ID, c.FIRST_NAME, c.LAST_NAME
            FROM {DB}.RAW.CUSTOMERS c JOIN {DB}.CURATED.CUSTOMER_METRICS_SUMMARY m ON m.CUSTOMER_ID = c.CUSTOMER_ID
            WHERE m.LATEST_SENTIMENT = 'positive' ORDER BY m.TOTAL_ANNUAL_PREMIUM DESC LIMIT 1
        )
        """
    ).to_pandas()


# ---------------------------------------------------------------------------
# Agent helpers
# ---------------------------------------------------------------------------
def run_agent(question, thread_id=None, parent_message_id=None):
    body = {"messages": [{"role": "user", "content": [{"type": "text", "text": question}]}]}
    if thread_id is not None:
        body["thread_id"] = thread_id
        body["parent_message_id"] = parent_message_id if parent_message_id is not None else 0
    body_json = json.dumps(body)
    create_thread = thread_id is None
    query = f"""
        SELECT TRY_PARSE_JSON(
            SNOWFLAKE.CORTEX.DATA_AGENT_RUN('{AGENT_FQN}', $${body_json}$$, {str(create_thread).upper()})
        ) AS RESP
    """
    row = session.sql(query).collect()[0]
    return json.loads(row["RESP"])


def render_agent_response(resp):
    content = resp.get("content", [])
    for block in content:
        btype = block.get("type")
        if btype == "text":
            st.markdown(block.get("text", ""))
        elif btype == "table":
            table = block.get("table", {})
            data = table.get("result_set", {}).get("data", [])
            cols = [c["name"] for c in table.get("result_set", {}).get("resultSetMetaData", {}).get("rowType", [])]
            if data and cols:
                st.dataframe(pd.DataFrame(data, columns=cols), width="stretch", hide_index=True)
        elif btype == "chart":
            spec_str = block.get("chart", {}).get("chart_spec")
            if spec_str:
                try:
                    st.vega_lite_chart(json.loads(spec_str), width="stretch")
                except Exception:
                    pass
    return resp.get("metadata", {})


# ---------------------------------------------------------------------------
# Session state / navigation helpers
# ---------------------------------------------------------------------------
if "active_tab" not in st.session_state:
    st.session_state.active_tab = TAB_PORTFOLIO
if "prefill_question" not in st.session_state:
    st.session_state.prefill_question = None


def jump_to_customer(customer_id, tab=TAB_360):
    st.session_state["pending_customer_id"] = customer_id
    st.session_state["pending_tab"] = tab
    st.rerun()


# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
st.markdown(
    """
    <div class="app-header">
        <h1>🏦 Customer 360 &amp; Next Best Action</h1>
        <p>Unified policyholder view for personalization, underwriting, and churn reduction</p>
    </div>
    """,
    unsafe_allow_html=True,
)

customers = load_customers()
customers["LABEL"] = (
    customers["FIRST_NAME"] + " " + customers["LAST_NAME"] + "  ·  " + customers["CUSTOMER_ID"]
    + "  ·  " + customers["CUSTOMER_SEGMENT"]
)
label_by_id = dict(zip(customers["CUSTOMER_ID"], customers["LABEL"]))

# Apply any pending programmatic customer selection *before* the selectbox
# widget below is instantiated -- Streamlit forbids writing to a widget's
# session_state key after that widget has already run in the current pass.
pending_id = st.session_state.pop("pending_customer_id", None)
if pending_id and label_by_id.get(pending_id):
    st.session_state["customer_select"] = label_by_id[pending_id]

with st.sidebar:
    st.markdown("### 🔍 Find a customer")
    st.caption("Click the box and type a name, ID, or segment — the list filters instantly.")
    label = st.selectbox(
        "Customer",
        options=customers["LABEL"].tolist(),
        label_visibility="collapsed",
        placeholder="Type to search...",
        key="customer_select",
    )
    customer_id = label.split("·")[1].strip() if label else None

    if customer_id:
        row = load_customer_by_id(customer_id).iloc[0]
        initials = (row["FIRST_NAME"][:1] + row["LAST_NAME"][:1]).upper()
        st.markdown(
            f"""
            <div class="customer-card">
                <div style="display:flex;align-items:center;gap:0.7rem;">
                    <div style="width:42px;height:42px;border-radius:50%;background:{PRIMARY};
                                color:white;display:flex;align-items:center;justify-content:center;
                                font-weight:700;font-size:1rem;flex-shrink:0;">{initials}</div>
                    <div>
                        <div style="font-weight:700;color:{DARK};">{row['FIRST_NAME']} {row['LAST_NAME']}</div>
                        <div style="font-size:0.8rem;color:#5a6b7a;">{row['CUSTOMER_ID']} · {row['CUSTOMER_SEGMENT']}</div>
                    </div>
                </div>
                <div style="margin-top:0.6rem;font-size:0.82rem;color:#5a6b7a;">
                    📍 {row['STATE']} &nbsp;·&nbsp; 🗓️ Since {row['CUSTOMER_SINCE']} &nbsp;·&nbsp; 💳 {row['CREDIT_SCORE_BAND']}
                </div>
            </div>
            """,
            unsafe_allow_html=True,
        )

    st.divider()
    demo_mode = st.toggle("🎬 Demo mode", value=False, help="Quick-jump to curated customers for a smooth live walkthrough.")
    if demo_mode:
        demo_df = load_demo_customers()
        demo_chips = {
            "highest_risk": ("🔴", "Highest churn risk"),
            "highest_value": ("💎", "Highest-value customer"),
            "largest_claim": ("🧾", "Largest claim"),
            "happiest": ("😊", "Happiest customer"),
        }
        st.caption("Jump straight to an interesting customer:")
        for _, drow in demo_df.iterrows():
            icon, text = demo_chips.get(drow["DEMO_TYPE"], ("👤", drow["DEMO_TYPE"]))
            st.markdown('<div class="demo-chip">', unsafe_allow_html=True)
            if st.button(f"{icon} {text}: {drow['FIRST_NAME']} {drow['LAST_NAME']}", width="stretch", key=f"demo_{drow['DEMO_TYPE']}"):
                jump_to_customer(drow["CUSTOMER_ID"])
            st.markdown("</div>", unsafe_allow_html=True)
        st.divider()

    st.caption(
        "Data: US policyholder demographics grounded in real 2021 NAIC state auto/home "
        "premium benchmarks and real ISO claim frequency/severity data; health premiums and "
        "claims bootstrap-sampled from a real individual-level US health cost dataset; "
        "AI-generated call transcripts enriched with Cortex AI_SENTIMENT / AI_CLASSIFY / AI_COMPLETE."
    )

pending_tab = st.session_state.pop("pending_tab", None)
if pending_tab:
    st.session_state["active_tab"] = pending_tab

tab_choice = st.radio(
    "Navigation",
    [TAB_PORTFOLIO, TAB_360, TAB_CHAT],
    horizontal=True,
    label_visibility="collapsed",
    key="active_tab",
)

# ---------------------------------------------------------------------------
# Tab: Portfolio
# ---------------------------------------------------------------------------
if tab_choice == TAB_PORTFOLIO:
    kpis = load_portfolio_kpis().iloc[0]
    claim_ratio = (kpis["TOTAL_CLAIMS_PAID"] / kpis["TOTAL_BOOK_PREMIUM"]) if kpis["TOTAL_BOOK_PREMIUM"] else 0

    k1, k2, k3, k4, k5 = st.columns(5)
    with k1:
        metric_card("Customers", f"{int(kpis['CUSTOMER_COUNT']):,}")
    with k2:
        metric_card("Book of business", f"${kpis['TOTAL_BOOK_PREMIUM']:,.0f}/yr")
    with k3:
        metric_card(
            "Revenue at risk",
            f"${kpis['TOTAL_REVENUE_AT_RISK']:,.0f}",
            variant="danger" if kpis["TOTAL_REVENUE_AT_RISK"] > 0.15 * kpis["TOTAL_BOOK_PREMIUM"] else "warn",
            delta=(f"{kpis['TOTAL_REVENUE_AT_RISK'] / kpis['TOTAL_BOOK_PREMIUM'] * 100:.1f}% of book", "#c53030"),
        )
    with k4:
        metric_card(
            "High-risk customers",
            int(kpis["HIGH_RISK_COUNT"]),
            variant="danger" if kpis["HIGH_RISK_COUNT"] > 0 else "good",
        )
    with k5:
        metric_card("Claim ratio", f"{claim_ratio * 100:.1f}%", variant="warn" if claim_ratio > 0.5 else "")

    st.markdown("")
    left, right = st.columns([1, 1])

    with left:
        st.markdown('<div class="section-title">🚦 Churn risk distribution</div>', unsafe_allow_html=True)
        churn_df = load_churn_distribution()
        order = ["Low Churn Risk", "Medium Churn Risk", "High Churn Risk", "Unknown"]
        churn_df["RISK"] = pd.Categorical(churn_df["RISK"], categories=order, ordered=True)
        churn_df = churn_df.sort_values("RISK")
        churn_df["RISK"] = churn_df["RISK"].astype(str)
        donut = (
            alt.Chart(churn_df)
            .mark_arc(innerRadius=70)
            .encode(
                theta=alt.Theta("CUSTOMERS:Q"),
                color=alt.Color(
                    "RISK:N",
                    scale=alt.Scale(domain=order, range=[RISK_COLOR["Low Churn Risk"], RISK_COLOR["Medium Churn Risk"], RISK_COLOR["High Churn Risk"], "#9aa5b1"]),
                    legend=alt.Legend(title=None),
                ),
                tooltip=["RISK", "CUSTOMERS"],
            )
            .properties(height=300)
        )
        st.altair_chart(donut, use_container_width=True)

    with right:
        st.markdown('<div class="section-title">📊 Book of business by segment</div>', unsafe_allow_html=True)
        seg_df = load_segment_breakdown()
        bar = (
            alt.Chart(seg_df)
            .mark_bar(cornerRadiusTopLeft=4, cornerRadiusTopRight=4)
            .encode(
                x=alt.X("CUSTOMER_SEGMENT:N", title=None, sort="-y"),
                y=alt.Y("PREMIUM:Q", title="Annual premium ($)"),
                color=alt.Color("CUSTOMER_SEGMENT:N", scale=alt.Scale(range=[DARK, PRIMARY, "#7fd0ef"]), legend=None),
                tooltip=["CUSTOMER_SEGMENT", "CUSTOMERS", "PREMIUM"],
            )
            .properties(height=300)
        )
        st.altair_chart(bar, use_container_width=True)

    st.markdown('<div class="section-title">🗺️ Book of business by state (top 15)</div>', unsafe_allow_html=True)
    state_df = load_state_breakdown().sort_values("PREMIUM", ascending=False).head(15)
    state_bar = (
        alt.Chart(state_df)
        .mark_bar(color=PRIMARY, cornerRadiusTopRight=4, cornerRadiusBottomRight=4)
        .encode(
            y=alt.Y("STATE:N", sort="-x", title=None),
            x=alt.X("PREMIUM:Q", title="Annual premium ($)"),
            tooltip=["STATE", "CUSTOMERS", "PREMIUM", "REVENUE_AT_RISK"],
        )
        .properties(height=420)
    )
    st.altair_chart(state_bar, use_container_width=True)

    st.markdown('<div class="section-title">⚠️ Customers needing attention</div>', unsafe_allow_html=True)
    st.caption("Ranked by a priority score blending churn risk, premium value, missed payments, and claims.")
    attention_df = load_attention_list(8)
    for _, arow in attention_df.iterrows():
        c1, c2, c3, c4 = st.columns([2.2, 1.6, 3.2, 1])
        with c1:
            st.markdown(f"**{arow['FIRST_NAME']} {arow['LAST_NAME']}**  \n`{arow['CUSTOMER_ID']}` · {arow['CUSTOMER_SEGMENT']}")
        with c2:
            st.markdown(
                f"{risk_badge_html(arow['LATEST_CHURN_RISK'])}<br/><span style='font-size:0.8rem;color:#5a6b7a;'>"
                f"${arow['TOTAL_ANNUAL_PREMIUM']:,.0f}/yr</span>",
                unsafe_allow_html=True,
            )
        with c3:
            st.caption(arow["NEXT_BEST_ACTION"] if pd.notna(arow["NEXT_BEST_ACTION"]) else "—")
        with c4:
            if st.button("View 360", key=f"attn_{arow['CUSTOMER_ID']}", width="stretch"):
                jump_to_customer(arow["CUSTOMER_ID"])

# ---------------------------------------------------------------------------
# Tab: Customer 360
# ---------------------------------------------------------------------------
elif tab_choice == TAB_360:
    if not customer_id:
        st.info("Select a customer from the sidebar to get started.")
        st.stop()

    cust_row = load_customer_by_id(customer_id).iloc[0]
    metrics_df = load_customer_metrics(customer_id)
    metrics = metrics_df.iloc[0] if not metrics_df.empty else None
    policies = load_policies(customer_id)
    claims = load_claims(customer_id)
    payments = load_payments(customer_id)
    interactions = load_interactions(customer_id)

    header_l, header_r = st.columns([3, 1])
    with header_l:
        st.markdown(f"#### {cust_row['FIRST_NAME']} {cust_row['LAST_NAME']}  ·  `{customer_id}`")
    with header_r:
        latest_risk = metrics["LATEST_CHURN_RISK"] if metrics is not None else None
        if latest_risk:
            st.markdown(
                f"<div style='text-align:right;'>{risk_badge_html(latest_risk)}</div>",
                unsafe_allow_html=True,
            )

    # KPIs are served from the CUSTOMER_METRICS_SUMMARY rollup table (a single
    # pre-aggregated row per customer) instead of recomputing SUM/COUNT over
    # the raw POLICIES/CLAIMS/PAYMENTS tables on every page load.
    k1, k2, k3, k4, k5 = st.columns(5)
    with k1:
        metric_card("Segment", cust_row["CUSTOMER_SEGMENT"])
    with k2:
        metric_card("Customer since", str(cust_row["CUSTOMER_SINCE"]))
    with k3:
        metric_card("Active policies", int(metrics["ACTIVE_POLICY_COUNT"]) if metrics is not None else 0)
    with k4:
        metric_card(
            "Total annual premium",
            f"${metrics['TOTAL_ANNUAL_PREMIUM']:,.0f}" if metrics is not None else "$0",
        )
    with k5:
        missed = int(metrics["MISSED_PAYMENT_COUNT"]) if metrics is not None else 0
        metric_card("Missed payments (12mo)", missed, variant="danger" if missed >= 2 else ("warn" if missed == 1 else ""))

    # Next Best Action, precomputed on the CUSTOMER_METRICS_SUMMARY dynamic
    # table via AI_COMPLETE, surfaced upfront instead of requiring a chat turn.
    if metrics is not None and pd.notna(metrics.get("NEXT_BEST_ACTION")):
        nba_col, btn_col = st.columns([5, 1])
        with nba_col:
            st.markdown(
                f"""
                <div class="nba-card">
                    <div class="nba-label">🎯 Recommended next best action &nbsp;·&nbsp; priority {metrics['PRIORITY_SCORE']:.0f}/100</div>
                    <div class="nba-action">{metrics['NEXT_BEST_ACTION']}</div>
                    <div class="nba-rationale">{metrics['NBA_RATIONALE']}</div>
                </div>
                """,
                unsafe_allow_html=True,
            )
        with btn_col:
            st.markdown("<div style='height:1.6rem'></div>", unsafe_allow_html=True)
            if st.button("💬 Discuss with AI", width="stretch", key="discuss_nba"):
                st.session_state.prefill_question = (
                    f"What is the next best action for customer {customer_id}, and why?"
                )
                st.session_state["pending_tab"] = TAB_CHAT
                st.rerun()

    left, right = st.columns(2)

    with left:
        st.markdown('<div class="section-title">📄 Policies</div>', unsafe_allow_html=True)
        with st.container(border=True):
            if policies.empty:
                st.caption("No policies on file.")
            else:
                st.dataframe(
                    policies,
                    width="stretch",
                    hide_index=True,
                    column_config={
                        "ANNUAL_PREMIUM": st.column_config.NumberColumn("Annual Premium", format="$%.2f"),
                        "COVERAGE_AMOUNT": st.column_config.NumberColumn("Coverage", format="$%.0f"),
                        "DEDUCTIBLE": st.column_config.NumberColumn("Deductible", format="$%.0f"),
                        "EFFECTIVE_DATE": st.column_config.DateColumn("Effective"),
                        "RENEWAL_DATE": st.column_config.DateColumn("Renewal"),
                    },
                )

        st.markdown('<div class="section-title">🧾 Claims</div>', unsafe_allow_html=True)
        with st.container(border=True):
            if claims.empty:
                st.caption("No claims on file.")
            else:
                st.dataframe(
                    claims,
                    width="stretch",
                    hide_index=True,
                    column_config={
                        "CLAIM_AMOUNT": st.column_config.NumberColumn("Claim Amount", format="$%.2f"),
                        "CLAIM_DATE": st.column_config.DateColumn("Claim Date"),
                    },
                )

    with right:
        st.markdown('<div class="section-title">💳 Payment history</div>', unsafe_allow_html=True)
        with st.container(border=True):
            if payments.empty:
                st.caption("No payment history on file.")
            else:
                st.dataframe(
                    payments,
                    width="stretch",
                    hide_index=True,
                    column_config={
                        "AMOUNT": st.column_config.NumberColumn("Amount", format="$%.2f"),
                        "DUE_DATE": st.column_config.DateColumn("Due"),
                        "PAID_DATE": st.column_config.DateColumn("Paid"),
                    },
                )

        st.markdown('<div class="section-title">📈 Sentiment trend</div>', unsafe_allow_html=True)
        with st.container(border=True):
            if interactions.empty:
                st.caption("No interactions on file.")
            else:
                trend = interactions.copy()
                trend["SENTIMENT_SCORE"] = trend["SENTIMENT_OVERALL"].map(SENTIMENT_SCORE).fillna(0)
                trend = trend.sort_values("INTERACTION_DATE")
                line = (
                    alt.Chart(trend)
                    .mark_area(line={"color": PRIMARY, "size": 2}, color=alt.Gradient(
                        gradient="linear",
                        stops=[alt.GradientStop(color="white", offset=0), alt.GradientStop(color=PRIMARY, offset=1)],
                        x1=1, x2=1, y1=1, y2=0,
                    ), opacity=0.25)
                    .encode(
                        x=alt.X("INTERACTION_DATE:T", title=None),
                        y=alt.Y("SENTIMENT_SCORE:Q", title=None, scale=alt.Scale(domain=[-1.2, 1.2])),
                    )
                )
                points = (
                    alt.Chart(trend)
                    .mark_line(point=alt.OverlayMarkDef(color=PRIMARY, size=60), color=PRIMARY, size=2)
                    .encode(
                        x="INTERACTION_DATE:T",
                        y="SENTIMENT_SCORE:Q",
                        tooltip=["INTERACTION_DATE", "SENTIMENT_OVERALL"],
                    )
                )
                st.altair_chart((line + points).properties(height=260), use_container_width=True)

    st.markdown('<div class="section-title">🗂️ Interaction history</div>', unsafe_allow_html=True)
    if interactions.empty:
        st.caption("No interactions on file.")
    else:
        for _, irow in interactions.iterrows():
            icon = CHANNEL_ICON.get(irow["CHANNEL"], "📌")
            with st.container(border=True):
                top1, top2 = st.columns([3, 2])
                with top1:
                    st.markdown(
                        f"**{icon} {irow['CHANNEL']}** · {irow['INTERACTION_DATE']} · "
                        f"*{irow['PRIMARY_INTENT']}*"
                    )
                with top2:
                    st.markdown(
                        f"<div style='text-align:right'>{sentiment_badge_html(irow['SENTIMENT_OVERALL'])} "
                        f"{risk_badge_html(irow['CHURN_RISK_LEVEL'])}</div>",
                        unsafe_allow_html=True,
                    )
                with st.expander("View transcript"):
                    st.text(irow["TRANSCRIPT_TEXT"])

# ---------------------------------------------------------------------------
# Tab: Chat / Next Best Action
# ---------------------------------------------------------------------------
elif tab_choice == TAB_CHAT:
    if not customer_id:
        st.info("Select a customer from the sidebar to get started.")
        st.stop()

    cust_row = load_customer_by_id(customer_id).iloc[0]

    st.markdown(
        f"Ask a question about **{cust_row['FIRST_NAME']} {cust_row['LAST_NAME']}** (or any aggregate question) "
        "and get an answer grounded in policy/claims data and call transcripts, plus a recommended **Next Best Action**."
    )

    sample_qs = [
        ("📋", f"Give me a 360 view of customer {customer_id}"),
        ("⚠️", f"Why might customer {customer_id} be at risk of churning?"),
        ("🎯", f"What is the next best action for customer {customer_id}?"),
    ]
    cols = st.columns(len(sample_qs))
    picked = None
    for col, (icon, q) in zip(cols, sample_qs):
        with col:
            st.markdown('<div class="chip-btn">', unsafe_allow_html=True)
            if st.button(f"{icon}  {q}", width="stretch", key=f"sample_{q}"):
                picked = q
            st.markdown("</div>", unsafe_allow_html=True)

    # Conversations are kept per customer, and multiple conversations per
    # customer are preserved (never wiped) -- "New conversation" just starts
    # another thread alongside the existing ones.
    if "conversations" not in st.session_state:
        st.session_state.conversations = {}
    if "active_conv_idx" not in st.session_state:
        st.session_state.active_conv_idx = {}

    def _new_conversation():
        return {"history": [], "thread_id": None, "parent_message_id": None, "label": None}

    if customer_id not in st.session_state.conversations:
        st.session_state.conversations[customer_id] = [_new_conversation()]
        st.session_state.active_conv_idx[customer_id] = 0

    convs = st.session_state.conversations[customer_id]

    st.markdown("")
    top_left, top_right = st.columns([3, 1])
    with top_left:
        conv_labels = [f"💬 {c['label']}" if c["label"] else f"🆕 New conversation {i + 1}" for i, c in enumerate(convs)]
        active_idx = st.selectbox(
            "Conversation",
            options=list(range(len(convs))),
            format_func=lambda i: conv_labels[i],
            index=st.session_state.active_conv_idx[customer_id],
            label_visibility="collapsed",
        )
        st.session_state.active_conv_idx[customer_id] = active_idx
    with top_right:
        if st.button("➕ New conversation", width="stretch"):
            convs.append(_new_conversation())
            active_idx = len(convs) - 1
            st.session_state.active_conv_idx[customer_id] = active_idx
            st.rerun()

    active_conv = convs[active_idx]

    prefill = st.session_state.pop("prefill_question", None)
    question = st.chat_input("Ask about this customer or the portfolio...") or picked or prefill

    chat_container = st.container(border=True, height=480 if active_conv["history"] else "content")
    with chat_container:
        if not active_conv["history"] and not question:
            st.markdown(
                "👋 &nbsp; Ask a question above or click one of the suggestions to get a "
                "data-grounded answer and a recommended Next Best Action."
            )
        for turn in active_conv["history"]:
            avatar = "🧑" if turn["role"] == "user" else "🏦"
            with st.chat_message(turn["role"], avatar=avatar):
                if turn["role"] == "user":
                    st.markdown(turn["content"])
                else:
                    render_agent_response(turn["resp"])

        if question:
            if active_conv["label"] is None:
                active_conv["label"] = question if len(question) <= 40 else question[:37] + "..."

            active_conv["history"].append({"role": "user", "content": question})
            with st.chat_message("user", avatar="🧑"):
                st.markdown(question)
            with st.chat_message("assistant", avatar="🏦"):
                with st.spinner("Analyzing policy data and interaction history..."):
                    resp = run_agent(
                        question,
                        thread_id=active_conv["thread_id"],
                        parent_message_id=active_conv["parent_message_id"],
                    )
                render_agent_response(resp)
            active_conv["history"].append({"role": "assistant", "resp": resp})

            metadata = resp.get("metadata", {})
            active_conv["thread_id"] = metadata.get("thread_id", active_conv["thread_id"])
            active_conv["parent_message_id"] = metadata.get(
                "assistant_message_id", active_conv["parent_message_id"]
            )
