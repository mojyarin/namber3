-- ============================================================
-- ナンバーズ3 分析アプリ DBスキーマ (PostgreSQL)
-- ============================================================

-- 過去の抽選結果
CREATE TABLE draws (
    id              SERIAL PRIMARY KEY,
    draw_no         INTEGER UNIQUE NOT NULL,      -- 第◯◯◯◯回
    draw_date       DATE NOT NULL,
    digit1          SMALLINT NOT NULL CHECK (digit1 BETWEEN 0 AND 9),
    digit2          SMALLINT NOT NULL CHECK (digit2 BETWEEN 0 AND 9),
    digit3          SMALLINT NOT NULL CHECK (digit3 BETWEEN 0 AND 9),
    straight_num    CHAR(3) NOT NULL,             -- '123' 形式
    box_type        VARCHAR(10) NOT NULL,         -- 'straight'/'box6'/'box3'/'box1'
    straight_payout INTEGER,                      -- 円
    box_payout      INTEGER,
    created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_draws_date ON draws (draw_date DESC);

-- 日次で計算した統計特徴量（数字ごと・桁ごと）
CREATE TABLE digit_stats (
    id              SERIAL PRIMARY KEY,
    calc_date       DATE NOT NULL,
    position        SMALLINT NOT NULL,   -- 1,2,3 (百/十/一の位) 0=全体
    digit           SMALLINT NOT NULL CHECK (digit BETWEEN 0 AND 9),
    freq_last_30    INTEGER,             -- 直近30回出現数
    freq_last_100   INTEGER,
    is_hot          BOOLEAN,
    is_cold         BOOLEAN,
    is_hipparu      BOOLEAN,             -- 前回引っ張り数字か
    UNIQUE (calc_date, position, digit)
);

-- AIが生成した候補（毎回の予測ロジック実行結果）
CREATE TABLE candidates (
    id              SERIAL PRIMARY KEY,
    target_draw_no  INTEGER NOT NULL,      -- 予測対象の回号
    generated_at    TIMESTAMPTZ DEFAULT now(),
    number          CHAR(3) NOT NULL,
    bet_type        VARCHAR(10) NOT NULL,  -- 'straight' / 'box'
    score           NUMERIC(6,4) NOT NULL, -- 0.0〜1.0 の統計的スコア
    rank            SMALLINT NOT NULL,     -- 1〜3位など
    reason_tags     TEXT[]                 -- ['hot','hipparu','wheel_adjacent']
);
CREATE INDEX idx_candidates_target ON candidates (target_draw_no);

-- バックテスト結果（予測 vs 実際）
CREATE TABLE backtests (
    id              SERIAL PRIMARY KEY,
    candidate_id    INTEGER REFERENCES candidates(id),
    draw_id         INTEGER REFERENCES draws(id),
    hit             BOOLEAN NOT NULL,
    hit_type        VARCHAR(10),           -- 'straight'/'box'/null
    payout          INTEGER DEFAULT 0,
    stake           INTEGER DEFAULT 200,   -- 1口あたり掛け金
    created_at      TIMESTAMPTZ DEFAULT now()
);

-- ユーザーのお気に入り・購入メモ
CREATE TABLE user_favorites (
    id              SERIAL PRIMARY KEY,
    user_id         VARCHAR(64) NOT NULL,  -- Firebase Auth UID
    number          CHAR(3) NOT NULL,
    bet_type        VARCHAR(10) NOT NULL,
    memo            TEXT,
    target_draw_no  INTEGER,
    created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_favorites_user ON user_favorites (user_id);
