import os
import pandas as pd
from sqlalchemy import create_engine, text

DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql+psycopg2://user:password@localhost:5432/numbers3"
)
engine = create_engine(DATABASE_URL, pool_pre_ping=True)


def fetch_draws(limit: int = 500) -> pd.DataFrame:
    query = text(
        """
        SELECT draw_no, draw_date, digit1, digit2, digit3
        FROM draws
        ORDER BY draw_no DESC
        LIMIT :limit
        """
    )
    with engine.connect() as conn:
        df = pd.read_sql(query, conn, params={"limit": limit})
    return df.sort_values("draw_no").reset_index(drop=True)


def save_candidates(target_draw_no: int, candidates: list) -> None:
    with engine.begin() as conn:
        for rank, c in enumerate(candidates, start=1):
            conn.execute(
                text(
                    """
                    INSERT INTO candidates
                        (target_draw_no, number, bet_type, score, rank, reason_tags)
                    VALUES
                        (:target_draw_no, :number, :bet_type, :score, :rank, :tags)
                    """
                ),
                {
                    "target_draw_no": target_draw_no,
                    "number": c.number,
                    "bet_type": c.bet_type,
                    "score": c.score,
                    "rank": rank,
                    "tags": c.reason_tags,
                },
            )


def fetch_next_draw_no() -> int:
    with engine.connect() as conn:
        result = conn.execute(text("SELECT MAX(draw_no) FROM draws")).scalar()
    return (result or 0) + 1
