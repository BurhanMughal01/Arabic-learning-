#!/bin/bash
# ============================================================
# Nūr — Data Validation Script
# Run before every push: bash validate.sh
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass(){ echo -e "${GREEN}✅ $1${NC}"; PASS=$((PASS+1)); }
fail(){ echo -e "${RED}❌ $1${NC}"; FAIL=$((FAIL+1)); }
warn(){ echo -e "${YELLOW}⚠️  $1${NC}"; WARN=$((WARN+1)); }
info(){ echo -e "${BLUE}ℹ️  $1${NC}"; }

echo "════════════════════════════════════════════════════════════"
echo "  NŪR — VALIDATION SUITE"
echo "  $(date)"
echo "════════════════════════════════════════════════════════════"
echo ""

cd "$(dirname "$0")" || exit 1

# ─── 1. FILE PRESENCE ───
echo "── 1. FILE PRESENCE ──"
for f in index.html data/top100.json sw.js manifest.json; do
  if [ -f "$f" ]; then
    SIZE=$(du -h "$f" | cut -f1)
    pass "$f present ($SIZE)"
  else
    fail "$f MISSING"
  fi
done
echo ""

# ─── 2. JSON PARSE ───
echo "── 2. JSON PARSING ──"
python3 << 'PYEOF' || FAIL=$((FAIL+1))
import json, sys
try:
    with open('data/top100.json', encoding='utf-8') as f:
        data = json.load(f)
    print(f"  Data loaded: {len(data)} entries")
    sys.exit(0)
except Exception as e:
    print(f"  ❌ JSON parse error: {e}")
    sys.exit(1)
PYEOF
if [ $? -eq 0 ]; then pass "JSON parses successfully"; else fail "JSON parse failed"; fi
echo ""

# ─── 3. DATA VALIDATION ───
echo "── 3. DATA VALIDATION ──"
python3 << 'PYEOF'
import json, sys, re

with open('data/top100.json', encoding='utf-8') as f:
    data = json.load(f)

fail = 0
warn = 0

# 3.1 Unique IDs
ids = [r['id'] for r in data]
if len(ids) == len(set(ids)):
    print(f"  ✅ Unique IDs: {len(ids)}")
else:
    dup = [i for i in set(ids) if ids.count(i) > 1]
    print(f"  ❌ Duplicate IDs: {dup}")
    fail += 1

# 3.2 Total entries
if len(data) == 100:
    print(f"  ✅ Total entries: 100")
else:
    print(f"  ⚠️  Total entries: {len(data)} (expected 100)")
    warn += 1

# 3.3 Required fields
REQ_TOP = ['id', 'lemma_ar', 'lemma_lat', 'lemma_bw', 'pos', 'meaning', 'freq', 'ayah']
REQ_AYAH = ['surah', 'ayah', 'word_num', 'word_ar', 'ar', 'ur', 'en', 'ref', 'surah_name_en']
REQ_MEANING = ['en', 'ur']
REQ_FREQ = ['count', 'source', 'method']

missing_top = {}
missing_ayah = {}
for r in data:
    rid = r['id']
    for fld in REQ_TOP:
        if fld not in r or r[fld] is None or (isinstance(r[fld], str) and not r[fld]):
            missing_top.setdefault(fld, []).append(rid)
    if 'ayah' in r and isinstance(r['ayah'], dict):
        for fld in REQ_AYAH:
            if fld not in r['ayah'] or r['ayah'][fld] is None:
                missing_ayah.setdefault(fld, []).append(rid)
    if 'meaning' in r and isinstance(r['meaning'], dict):
        for fld in REQ_MEANING:
            if fld not in r['meaning'] or not r['meaning'][fld]:
                print(f"  ❌ ID {rid}: missing meaning.{fld}")
                fail += 1

if missing_top:
    for fld, rids in missing_top.items():
        print(f"  ⚠️  Missing top-level '{fld}' in {len(rids)} entries: {rids[:5]}...")
        warn += 1
else:
    print(f"  ✅ All top-level required fields present")

if missing_ayah:
    for fld, rids in missing_ayah.items():
        print(f"  ❌ Missing ayah.{fld} in {len(rids)} entries: {rids[:5]}")
        fail += 1
else:
    print(f"  ✅ All ayah fields present")

# 3.4 word_num bounds (1 to total words in ayah)
bad_wn = []
for r in data:
    wn = r['ayah'].get('word_num')
    ar = r['ayah'].get('ar', '')
    total_words = len(ar.split())
    if not isinstance(wn, int) or wn < 1 or wn > total_words:
        bad_wn.append((r['id'], wn, total_words))
if bad_wn:
    print(f"  ❌ Invalid word_num in {len(bad_wn)} entries: {bad_wn[:5]}")
    fail += 1
else:
    print(f"  ✅ All word_num values within bounds")

# 3.5 word_ar matches the token at word_num
bad_match = []
for r in data:
    wn = r['ayah'].get('word_num')
    ar = r['ayah'].get('ar', '')
    expected = r['ayah'].get('word_ar', '')
    words = ar.split()
    if 0 < wn <= len(words):
        actual = words[wn-1]
        if actual != expected:
            bad_match.append((r['id'], wn, expected, actual))
if bad_match:
    print(f"  ❌ word_ar mismatch in {len(bad_match)} entries:")
    for m in bad_match[:5]:
        print(f"      ID {m[0]}: word_num={m[1]} expected='{m[2]}' actual='{m[3]}'")
    fail += 1
else:
    print(f"  ✅ word_ar matches token at word_num for all 100")

# 3.6 Frequency range
counts = [r['freq']['count'] for r in data]
print(f"  ✅ Frequency range: {min(counts)}–{max(counts)} (total: {sum(counts):,})")

# 3.7 No empty meanings
empty_meaning = [r['id'] for r in data if not r['meaning'].get('en') or r['meaning']['en'] == '—']
if empty_meaning:
    print(f"  ❌ Empty meanings: {empty_meaning}")
    fail += 1
else:
    print(f"  ✅ All 100 have non-empty meanings")

# 3.8 Surah/ayah valid range
bad_ref = []
for r in data:
    s = r['ayah'].get('surah')
    a = r['ayah'].get('ayah')
    if not (1 <= s <= 114):
        bad_ref.append((r['id'], s, a, 'surah'))
    if not (1 <= a <= 286):  # max ayahs in any surah
        bad_ref.append((r['id'], s, a, 'ayah'))
if bad_ref:
    print(f"  ❌ Invalid refs: {bad_ref[:5]}")
    fail += 1
else:
    print(f"  ✅ All surah/ayah references in valid range")

# 3.9 Inline data equality
try:
    html = open('index.html', encoding='utf-8').read()
    m = re.search(r'window\.__INLINE_DATA__\s*=\s*(\[.*?\]);', html, re.DOTALL)
    if m:
        inline = json.loads(m.group(1))
        if inline == data:
            print(f"  ✅ Inline data == standalone JSON (both {len(inline)} entries)")
        else:
            print(f"  ❌ Inline data != standalone JSON")
            fail += 1
    else:
        print(f"  ⚠️  Inline data not found in index.html")
        warn += 1
except Exception as e:
    print(f"  ⚠️  Inline check skipped: {e}")
    warn += 1

sys.exit(1 if fail else 0)
PYEOF

if [ $? -eq 0 ]; then
  pass "Data validation passed"
else
  fail "Data validation found errors"
fi
echo ""

# ─── 4. LIVE DEPLOYMENT CHECK ───
echo "── 4. LIVE DEPLOYMENT CHECK ──"
BASE="https://burhanmughal01.github.io/Arabic-learning-/"

# 4.1 Main page
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE")
if [ "$STATUS" = "200" ]; then
  pass "Main page HTTP $STATUS"
else
  fail "Main page HTTP $STATUS"
fi

# 4.2 JSON endpoint
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${BASE}data/top100.json")
if [ "$STATUS" = "200" ]; then
  pass "top100.json HTTP $STATUS"
else
  fail "top100.json HTTP $STATUS"
fi

# 4.3 Service Worker
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${BASE}sw.js")
if [ "$STATUS" = "200" ]; then
  pass "sw.js HTTP $STATUS"
else
  fail "sw.js HTTP $STATUS"
fi

# 4.4 Manifest
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${BASE}manifest.json")
if [ "$STATUS" = "200" ]; then
  pass "manifest.json HTTP $STATUS"
else
  fail "manifest.json HTTP $STATUS"
fi
echo ""

# ─── 5. CODE MARKERS ───
echo "── 5. CODE MARKERS (search in live HTML) ──"
LIVE_HTML=$(curl -s "$BASE")

check_marker(){
  local name="$1"
  local pattern="$2"
  local expected="$3"
  local count=$(echo "$LIVE_HTML" | grep -c "$pattern")
  if [ "$count" -ge "$expected" ]; then
    pass "$name ($count)"
  else
    fail "$name (found $count, expected ≥ $expected)"
  fi
}

check_marker "Audio URL: Alafasy_128kbps" "Alafasy_128kbps" 1
check_marker "Schema v5" "nur_schema_v5" 1
check_marker "saveCurrentId" "saveCurrentId" 2
check_marker "nur_completed_v5" "nur_completed_v5" 1
check_marker "getWordById" "getWordById" 2
check_marker "SW registration" "serviceWorker.register" 1
check_marker "Manifest link" "manifest.json" 1
check_marker "Sources & Attribution" "Sources & Attribution" 1
echo ""

# ─── BAD MARKERS (should NOT be present) ───
echo "── 6. OLD/BAD MARKERS (should NOT be present) ──"
if echo "$LIVE_HTML" | grep -q "Mishary_Alafasy"; then
  fail "Old audio folder 'Mishary_Alafasy' still present"
else
  pass "Old audio folder removed"
fi

if echo "$LIVE_HTML" | grep -q "i!==wid"; then
  fail "Review bug 'i!==wid' still present"
else
  pass "Review bug fixed (no i!==wid)"
fi

if echo "$LIVE_HTML" | grep -q "Date.now()"; then
  warn "Date.now() still present (cache-buster may break offline)"
else
  pass "No Date.now() cache-buster"
fi
echo ""

# ─── SUMMARY ───
echo "════════════════════════════════════════════════════════════"
echo "  SUMMARY"
echo "════════════════════════════════════════════════════════════"
echo -e "  ${GREEN}Passed: ${PASS}${NC}"
echo -e "  ${YELLOW}Warnings: ${WARN}${NC}"
echo -e "  ${RED}Failed: ${FAIL}${NC}"
echo ""

if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}🎉 ALL VALIDATIONS PASSED${NC}"
  exit 0
else
  echo -e "${RED}❌ VALIDATION FAILED — ${FAIL} issue(s) found${NC}"
  exit 1
fi
