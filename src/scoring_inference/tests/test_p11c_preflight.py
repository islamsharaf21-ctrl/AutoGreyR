import csv
import hashlib
import importlib.util
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCORER = ROOT / "AUTOGREY_V2_P11C_FROZEN_CONFIRMATORY_SCORING_R1.py"


def load_module():
    spec = importlib.util.spec_from_file_location("p11c_task2", SCORER)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()


def write_csv(path: Path, header, rows):
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=header, lineterminator="\n")
        w.writeheader(); w.writerows(rows)


def read_csv_rows(path: Path):
    with path.open("r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def refresh_manifest_member(manifest: Path, member: Path):
    lines=[]
    for line in manifest.read_text(encoding="utf-8").splitlines():
        h,n=line.split(None,1); n=n.strip()
        if n==member.name:
            h=sha256(member)
        lines.append(f"{h}  {n}")
    manifest.write_text("\n".join(lines)+"\n",encoding="utf-8")


def build_fixture(base: Path):
    m = load_module()
    p10 = base / "p10"; p11a1 = base / "p11a1"; p11a2 = base / "p11a2"; p11b = base / "p11b"
    for d in (p10,p11a1,p11a2,p11b): d.mkdir()

    # Minimal outer identities.
    (p10 / m.NAMES["p10a"]).write_text("{}\n", encoding="utf-8")
    (p10 / m.NAMES["p10contract"]).write_text("{}\n", encoding="utf-8")
    (p11a1 / m.NAMES["dev_index"]).write_text("parent_id,source_id,h,M\nA,S,1,1\n", encoding="utf-8")
    (p11a1 / m.NAMES["dev_binary"]).write_bytes(struct.pack("<d", 1.0))
    (p11a2 / m.NAMES["p11a2_evidence"]).write_text("P11A2_FINAL_CLASSIFICATION=PASS\n", encoding="utf-8")

    parents = ["A","B","C","D","E"]
    deployed = ["A","B"]
    target_rows = [{"parent_id":p,"source_id":"S","h":"1"} for p in parents]
    write_csv(p11b / m.NAMES["target_index"], ["parent_id","source_id","h"], target_rows)
    (p11b / m.NAMES["target_binary"]).write_bytes(b"DO_NOT_READ_NUMERICALLY")
    (p11b / m.NAMES["target_audit"]).write_text(json.dumps({"P11B_RESULT":"PASS","REALBENCH3_TARGET_VALUES_OPENED":True})+"\n", encoding="utf-8")
    (p11b / m.NAMES["p11b_evidence"]).write_text("P11B_RESULT=PASS\nREALBENCH3_TARGET_VALUES_OPENED=TRUE\n", encoding="utf-8")

    auto=[]; glob=[]; ng=[]; sub=[]; grey=[]; act=[]
    for p in parents:
        h="1"
        elig = p in deployed
        sub.append({
            "parent_id":p,"source_id":"S","h":h,
            "clean_h_n":"5","clean_source_n":"5","clean_source_x_h_n":"5",
            "selection_pair_eligible":str(elig).upper(),"selection_h_n":"2","selection_source_n":"2","selection_source_x_h_n":"2",
            "selection_h_inferential_eligible":"FALSE","selection_source_inferential_eligible":"FALSE","selection_source_x_h_inferential_eligible":"FALSE",
            "practical_pair_eligible":str(elig).upper(),"practical_h_n":"2","practical_source_n":"2","practical_source_x_h_n":"2",
            "practical_h_inferential_eligible":"FALSE","practical_source_inferential_eligible":"FALSE","practical_source_x_h_inferential_eligible":"FALSE",
        })
        act.append({
            "parent_id":p,"source_id":"S","h":h,"M":"1","n_D":"10",
            "available_pre_collision":"1","retained_post_collision":("1" if elig else "0"),
            "resolution_status":("SELECTOR_MAY_ACT_LATER" if elig else "ABSTAIN_NO_GREY"),
            "retained_groups":("SG01_CONT_GM" if elig else ""),"removed_groups":"",
            "selector_pair_eligible":str(elig).upper(),"practical_pair_eligible":str(elig).upper(),"ng10_status":("OK_3OF3" if elig else "")
        })
        if elig:
            fh = hashlib.sha256((p+"|SG01_CONT_GM|1").encode()).hexdigest().upper()
            auto.append({"parent_id":p,"source_id":"S","h":h,"action_count":"1","selection_mode":"SINGLETON","selected_group":"SG01_CONT_GM","predicted_log1p_regret":"0","forecast_sha256":fh})
            glob.append({"parent_id":p,"source_id":"S","h":h,"action_count":"1","selection_mode":"SINGLETON","selected_group":"SG01_CONT_GM","forecast_sha256":fh})
            ngfh = hashlib.sha256((p+"|NG10|1").encode()).hexdigest().upper()
            ng.append({"parent_id":p,"source_id":"S","h":h,"status":"OK_3OF3","components_successful":"3","used":"THETA+ETS+ARIMA","component_statuses":"OK;OK;OK","step":"1","forecast":"1.0","forecast_sha256":ngfh})
            grey.append({"parent_id":p,"source_id":"S","h":h,"group":"SG01_CONT_GM","step":"1","forecast":"1.0","forecast_sha256":fh})

    files = {
        "autogrey": (m.NAMES["autogrey"], m.HEADERS["autogrey"], auto),
        "global": (m.NAMES["global"], m.HEADERS["global"], glob),
        "ng10": (m.NAMES["ng10"], m.HEADERS["ng10"], ng),
        "subgroup": (m.NAMES["subgroup"], m.HEADERS["subgroup"], sub),
        "grey": (m.NAMES["grey"], m.HEADERS["grey"], grey),
        "actionability": (m.NAMES["actionability"], m.HEADERS["actionability"], act),
    }
    for role,(name,header,rows) in files.items():
        write_csv(p11a2/name, header, rows)

    # P11-A2 manifest includes the six science files + evidence (7 entries in fixture).
    manifest_entries=[]
    for role in ["autogrey","global","ng10","subgroup","grey","actionability"]:
        p=p11a2/m.NAMES[role]; manifest_entries.append((sha256(p),p.name))
    ev=p11a2/m.NAMES["p11a2_evidence"]; manifest_entries.append((sha256(ev),ev.name))
    (p11a2/m.NAMES["p11a2_manifest"]).write_text("\n".join(f"{h}  {n}" for h,n in manifest_entries)+"\n", encoding="utf-8")

    # P11-B manifest can be minimal fixture listing target artifacts.
    b_entries=[]
    for role in ["target_index","target_binary","target_audit","p11b_evidence"]:
        p=p11b/m.NAMES[role]; b_entries.append((sha256(p),p.name))
    (p11b/m.NAMES["p11b_manifest"]).write_text("\n".join(f"{h}  {n}" for h,n in b_entries)+"\n", encoding="utf-8")

    r4 = base / m.NAMES["r4_evidence"]
    r4.write_bytes(b"fixture-r4-pass")

    expected = {key: sha256(folder / m.NAMES[key]) for key,folder in [
        ("p10a",p10),("p10contract",p10),("dev_index",p11a1),("dev_binary",p11a1),
        ("p11a2_evidence",p11a2),("p11a2_manifest",p11a2),
        ("target_index",p11b),("target_binary",p11b),("target_audit",p11b),("p11b_evidence",p11b),("p11b_manifest",p11b),
        ("autogrey",p11a2),("global",p11a2),("ng10",p11a2),("subgroup",p11a2),("grey",p11a2),("actionability",p11a2),
    ]}
    expected["r4_evidence"] = sha256(r4)
    cfg = m.EntryGateConfig(expected_hashes=expected, manifest_entry_n=7, full_census_n=5, deployed_n=2, nondeployed_n=3)
    paths = m.EntryPaths(p10=p10,p11a1=p11a1,p11a2=p11a2,p11b=p11b,r4_evidence=r4)
    return m, paths, cfg


class TestManifestBoundPreflight(unittest.TestCase):
    def test_valid_fixture_passes_without_reading_target_binary_numeric_values(self):
        with tempfile.TemporaryDirectory() as td:
            m, paths, cfg = build_fixture(Path(td))
            state=m.verify_entry_gate(paths, config=cfg)
            self.assertEqual(len(state.full_parent_ids),5)
            self.assertEqual(len(state.deployed_parent_ids),2)
            self.assertEqual(state.target_binary_numeric_reads,0)

    def test_wrong_science_schema_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            m, paths, cfg = build_fixture(Path(td))
            p=paths.p11a2/m.NAMES["actionability"]
            text=p.read_text(encoding="utf-8").replace("selector_pair_eligible","selection_pair_eligible",1)
            p.write_text(text,encoding="utf-8")
            cfg.expected_hashes["actionability"]=sha256(p)
            man=paths.p11a2/m.NAMES["p11a2_manifest"]
            refresh_manifest_member(man,p)
            cfg.expected_hashes["p11a2_manifest"]=sha256(man)
            with self.assertRaisesRegex(AssertionError,"schema mismatch"):
                m.verify_entry_gate(paths, config=cfg)

    def test_population_mismatch_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            m, paths, cfg = build_fixture(Path(td))
            p=paths.p11a2/m.NAMES["global"]
            rows=read_csv_rows(p)[:-1]
            write_csv(p,m.HEADERS["global"],rows)
            cfg.expected_hashes["global"]=sha256(p)
            # refresh manifest hash/member hash to isolate population failure
            man=paths.p11a2/m.NAMES["p11a2_manifest"]
            refresh_manifest_member(man,p)
            cfg.expected_hashes["p11a2_manifest"]=sha256(man)
            with self.assertRaisesRegex(AssertionError,"deployed parent"):
                m.verify_entry_gate(paths, config=cfg)

    def test_missing_forecast_step_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            m, paths, cfg = build_fixture(Path(td))
            p=paths.p11a2/m.NAMES["ng10"]
            rows=read_csv_rows(p)
            rows[0]["step"]="2"
            write_csv(p,m.HEADERS["ng10"],rows)
            cfg.expected_hashes["ng10"]=sha256(p)
            man=paths.p11a2/m.NAMES["p11a2_manifest"]
            refresh_manifest_member(man,p)
            cfg.expected_hashes["p11a2_manifest"]=sha256(man)
            with self.assertRaisesRegex(AssertionError,"NG10: step vector mismatch"):
                m.verify_entry_gate(paths, config=cfg)

    def test_decision_forecast_hash_mismatch_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            m, paths, cfg = build_fixture(Path(td))
            p=paths.p11a2/m.NAMES["autogrey"]
            rows=read_csv_rows(p)
            rows[0]["forecast_sha256"]="0"*64
            write_csv(p,m.HEADERS["autogrey"],rows)
            cfg.expected_hashes["autogrey"]=sha256(p)
            man=paths.p11a2/m.NAMES["p11a2_manifest"]
            refresh_manifest_member(man,p)
            cfg.expected_hashes["p11a2_manifest"]=sha256(man)
            with self.assertRaisesRegex(AssertionError,"decision/forecast hash mismatch"):
                m.verify_entry_gate(paths, config=cfg)

    def test_subgroup_actionability_eligibility_disagreement_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            m, paths, cfg = build_fixture(Path(td))
            p=paths.p11a2/m.NAMES["actionability"]
            rows=read_csv_rows(p)
            rows[0]["selector_pair_eligible"]="FALSE"
            write_csv(p,m.HEADERS["actionability"],rows)
            cfg.expected_hashes["actionability"]=sha256(p)
            man=paths.p11a2/m.NAMES["p11a2_manifest"]
            refresh_manifest_member(man,p)
            cfg.expected_hashes["p11a2_manifest"]=sha256(man)
            with self.assertRaisesRegex(AssertionError,"eligibility disagreement"):
                m.verify_entry_gate(paths, config=cfg)

    def test_manifest_member_tamper_fails_before_alignment(self):
        with tempfile.TemporaryDirectory() as td:
            m, paths, cfg = build_fixture(Path(td))
            p=paths.p11a2/m.NAMES["p11a2_evidence"]
            p.write_text("tampered\n",encoding="utf-8")
            with self.assertRaisesRegex(AssertionError,"manifest member hash mismatch|SHA-256 mismatch"):
                m.verify_entry_gate(paths, config=cfg)

if __name__ == "__main__":
    unittest.main()
