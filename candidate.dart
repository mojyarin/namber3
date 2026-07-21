"""
ナンバーズ3 統計分析・候補スコアリングロジック
--------------------------------------------------
注意:
  ナンバーズ3は各回が独立事象の抽選であり、過去データから将来の当選番号を
  統計的に「予測」することはできない。本モジュールが算出する score は
  あくまで「過去傾向との一致度」を表す統計指標であり、当選確率の向上を
  意味しない。UI表示・API応答では必ずこの前提を明示すること。
"""
from __future__ import annotations
import itertools
from dataclasses import dataclass, field
from collections import Counter
import pandas as pd
import numpy as np


# ---------------------------------------------------------------
# 1. 特徴量計算
# ---------------------------------------------------------------

def compute_digit_frequency(draws_df: pd.DataFrame, window: int = 30) -> pd.DataFrame:
    """直近 window 回における桁ごとの数字出現回数を計算する。

    draws_df: columns = [draw_no, digit1, digit2, digit3] (draw_no昇順)
    return: index=digit(0-9), columns=[pos1,pos2,pos3,total]
    """
    recent = draws_df.sort_values("draw_no").tail(window)
    counts = pd.DataFrame(0, index=range(10), columns=["pos1", "pos2", "pos3"])
    for pos, col in enumerate(["digit1", "digit2", "digit3"], start=1):
        vc = recent[col].value_counts()
        counts[f"pos{pos}"] = vc.reindex(range(10), fill_value=0)
    counts["total"] = counts.sum(axis=1)
    return counts


def classify_hot_cold(freq: pd.DataFrame, hot_top_n: int = 3, cold_bottom_n: int = 3):
    """total列を基準にHot(頻出)/Cold(停滞)数字を分類する。"""
    ranked = freq["total"].sort_values(ascending=False)
    hot = set(ranked.head(hot_top_n).index)
    cold = set(ranked.tail(cold_bottom_n).index)
    return hot, cold


def find_hipparu_digits(draws_df: pd.DataFrame) -> set[int]:
    """引っ張り数字: 前回の当選数字のうち、今回も含まれる可能性を評価するための
    「前回出現した数字集合」を返す(直近1回分)。"""
    last = draws_df.sort_values("draw_no").iloc[-1]
    return {int(last.digit1), int(last.digit2), int(last.digit3)}


# 風車盤(数字選択式抽選機)上の物理配置。
# ナンバーズの抽選機は0-9の球が円環上に配置されており、隣接球が
# 連続して出やすいという俗説がある。これも「仮説」として扱い、
# reason_tagsに記録した上でバックテストで有効性を検証する運用とする。
WHEEL_ORDER = [0, 5, 1, 6, 2, 7, 3, 8, 4, 9]  # 一般に言われる配置例(要実機検証)
WHEEL_POS = {d: i for i, d in enumerate(WHEEL_ORDER)}


def wheel_adjacent(digit: int, distance: int = 1) -> set[int]:
    idx = WHEEL_POS[digit]
    n = len(WHEEL_ORDER)
    return {WHEEL_ORDER[(idx + d) % n] for d in (-distance, distance)}


# ---------------------------------------------------------------
# 2. 「選ばれやすい数字」の回避的補正(参考情報)
# ---------------------------------------------------------------
# 重要: ナンバーズ3は固定配当制のため、人気/不人気による配当額の変動は
# ロト6/7のような大きな影響を持たない。以下の関数は「参考スコア」として
# UIに補助表示するのみに留め、期待値計算の主要因には使わない。

def popularity_penalty(number: str) -> float:
    """誕生日・ゾロ目・連番など『人が選びやすい』組み合わせに小さな参考ペナルティを付与。
    ※ナンバーズ3では配当固定のため実際の期待値には影響しない参考指標。"""
    d = [int(c) for c in number]
    penalty = 0.0
    if d[0] == d[1] == d[2]:
        penalty += 0.05  # ゾロ目
    if (d[1] - d[0] == 1) and (d[2] - d[1] == 1):
        penalty += 0.03  # 連続数字
    if all(x <= 12 for x in d[:2]):
        penalty += 0.01  # 誕生日的組合せ
    return penalty


# ---------------------------------------------------------------
# 3. 候補生成・スコアリング
# ---------------------------------------------------------------

@dataclass
class Candidate:
    number: str
    bet_type: str  # 'straight' or 'box'
    score: float
    reason_tags: list[str] = field(default_factory=list)


def score_candidate(number: str, freq: pd.DataFrame, hot: set, cold: set,
                     hipparu: set) -> Candidate:
    d = [int(c) for c in number]
    tags = []
    score = 0.0

    # 桁別出現頻度に基づく統計スコア(正規化)
    for pos, val in zip(["pos1", "pos2", "pos3"], d):
        pos_freq = freq.loc[val, pos]
        score += pos_freq / freq[pos].sum() if freq[pos].sum() else 0

    if any(x in hot for x in d):
        score += 0.1
        tags.append("hot")
    if any(x in cold for x in d):
        score -= 0.05
        tags.append("cold")
    if any(x in hipparu for x in d):
        score += 0.05
        tags.append("hipparu")

    # 風車盤隣接ボーナス(仮説ロジック・小さめの重み)
    for x in d:
        if hipparu & wheel_adjacent(x):
            score += 0.02
            tags.append("wheel_adjacent")
            break

    score -= popularity_penalty(number)
    score = float(np.clip(score, 0, 1))
    return Candidate(number=number, bet_type="straight", score=score, reason_tags=tags)


def generate_top_candidates(draws_df: pd.DataFrame, top_n: int = 3,
                             window: int = 30) -> list[Candidate]:
    freq = compute_digit_frequency(draws_df, window=window)
    hot, cold = classify_hot_cold(freq)
    hipparu = find_hipparu_digits(draws_df)

    all_numbers = [f"{a}{b}{c}" for a, b, c in itertools.product(range(10), repeat=3)]
    scored = [score_candidate(n, freq, hot, cold, hipparu) for n in all_numbers]
    scored.sort(key=lambda c: c.score, reverse=True)

    # ストレート上位N
    straight_top = scored[:top_n]

    # ボックス用: 同じ数字の組合せ(並び違い)をまとめて代表スコア(最大値)で評価
    box_scores: dict[str, float] = {}
    box_tags: dict[str, list[str]] = {}
    for c in scored:
        key = "".join(sorted(c.number))
        if key not in box_scores or c.score > box_scores[key]:
            box_scores[key] = c.score
            box_tags[key] = c.reason_tags
    box_ranked = sorted(box_scores.items(), key=lambda kv: kv[1], reverse=True)
    box_top = [
        Candidate(number=k, bet_type="box", score=v, reason_tags=box_tags[k])
        for k, v in box_ranked[:top_n]
    ]

    return straight_top + box_top


# ---------------------------------------------------------------
# 4. バックテスト
# ---------------------------------------------------------------

def run_backtest(draws_df: pd.DataFrame, window: int = 30,
                  stake_per_bet: int = 200) -> dict:
    """各回について「その回より前のデータのみ」を使い候補を生成し、
    実際の結果と照合して的中率・回収率を算出する(リーク防止)。"""
    draws_df = draws_df.sort_values("draw_no").reset_index(drop=True)
    results = []

    for i in range(window, len(draws_df)):
        history = draws_df.iloc[:i]
        actual = draws_df.iloc[i]
        candidates = generate_top_candidates(history, top_n=3, window=window)

        actual_straight = f"{actual.digit1}{actual.digit2}{actual.digit3}"
        actual_box = "".join(sorted(actual_straight))

        for c in candidates:
            hit = False
            payout = 0
            if c.bet_type == "straight" and c.number == actual_straight:
                hit, payout = True, 900 * stake_per_bet // 200  # 理論配当例
            elif c.bet_type == "box" and c.number == actual_box:
                hit, payout = True, 150 * stake_per_bet // 200
            results.append({
                "draw_no": int(actual.draw_no),
                "bet_type": c.bet_type,
                "number": c.number,
                "hit": hit,
                "payout": payout,
                "stake": stake_per_bet,
            })

    df = pd.DataFrame(results)
    total_stake = df["stake"].sum()
    total_payout = df["payout"].sum()
    return {
        "total_bets": len(df),
        "hit_count": int(df["hit"].sum()),
        "hit_rate": float(df["hit"].mean()) if len(df) else 0.0,
        "total_stake": int(total_stake),
        "total_payout": int(total_payout),
        "roi": float(total_payout / total_stake) if total_stake else 0.0,
    }
