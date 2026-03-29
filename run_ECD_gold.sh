#!/usr/bin/env bash
set -euo pipefail


###################### USAGE ################################

usage() {
  cat <<'USAGE'
Usage:
  bash run_ECD.sh \
    --legacy-input-dir /path/to/input \
    --project-name test \
    [--project-date YYYYMMDD] \
    [--calc-date YYYYMMDD] \
    [--solvent methanol] \
    [--charge 0] \
    [--mult 1] \
    [--crest-mode precise] \
    [--ewin-input 20] \
    [--orca-cmd /path/to/orca] \
    [--max-jobs 3]

Required:
  --legacy-input-dir   Directory containing input mol2/csv files
  --project-name       Prefix of input files, e.g. test -> test.mol2 or test-*.mol2

Optional:
  --project-date       Default: today (YYYYMMDD)
  --calc-date          Default: today (YYYYMMDD)
  --solvent            Default: methanol
  --charge             Default: 0
  --mult               Default: 1
  --crest-mode         fast | precise | ultra ; default: precise
  --ewin-input         Default: 20
  --orca-cmd           Default: /home/soft/orca_6_1_1_linux_x86-64_shared_openmpi418/orca
  --max-jobs           Default: 3
  -h, --help           Show this help

Examples:
  # 首次运行：日期用系统当天
  bash run_ECD.sh \
    --legacy-input-dir /data/input \
    --project-name test

  # 复跑指定日期项目
  bash run_ECD.sh \
    --legacy-input-dir /data/input \
    --project-date 20260322 \
    --calc-date 20260322 \
    --project-name test
USAGE
}

###################### PARAMETERS ################################

PROJECT_DATE="$(date +%Y%m%d)"
CALC_DATE="$(date +%Y%m%d)"
PROJECT_NAME=""
LEGACY_INPUT_DIR=""
SOLVENT="methanol"
CHARGE=0
MULT=1
CREST_MODE="precise"
EWIN_INPUT=20
ORCA_CMD="/home/soft/orca_6_1_1_linux_x86-64_shared_openmpi418/orca"
MAX_JOBS=3

###################### ARGUMENT PARSING ################################

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-date) PROJECT_DATE="$2"; shift 2 ;;
    --calc-date) CALC_DATE="$2"; shift 2 ;;
    --project-name) PROJECT_NAME="$2"; shift 2 ;;
    --legacy-input-dir) LEGACY_INPUT_DIR="$2"; shift 2 ;;
    --solvent) SOLVENT="$2"; shift 2 ;;
    --charge) CHARGE="$2"; shift 2 ;;
    --mult|--multiplicity) MULT="$2"; shift 2 ;;
    --crest-mode) CREST_MODE="$2"; shift 2 ;;
    --ewin-input) EWIN_INPUT="$2"; shift 2 ;;
    --orca-cmd) ORCA_CMD="$2"; shift 2 ;;
    --max-jobs) MAX_JOBS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[ERROR] Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

###################### INPUT VALIDATION ################################

[[ -n "$LEGACY_INPUT_DIR" ]] || { echo "[ERROR] --legacy-input-dir is required" >&2; usage; exit 1; }
[[ -n "$PROJECT_NAME" ]] || { echo "[ERROR] --project-name is required" >&2; usage; exit 1; }

[[ "$PROJECT_DATE" =~ ^[0-9]{8}$ ]] || { echo "[ERROR] --project-date must be YYYYMMDD" >&2; exit 1; }
[[ "$CALC_DATE" =~ ^[0-9]{8}$ ]] || { echo "[ERROR] --calc-date must be YYYYMMDD" >&2; exit 1; }
[[ "$CHARGE" =~ ^-?[0-9]+$ ]] || { echo "[ERROR] --charge must be integer" >&2; exit 1; }
[[ "$MULT" =~ ^[0-9]+$ ]] || { echo "[ERROR] --mult must be positive integer" >&2; exit 1; }
[[ "$MAX_JOBS" =~ ^[0-9]+$ ]] || { echo "[ERROR] --max-jobs must be positive integer" >&2; exit 1; }

case "$CREST_MODE" in
  fast|precise|ultra) ;;
  *) echo "[ERROR] --crest-mode must be one of: fast precise ultra" >&2; exit 1 ;;
esac

LEGACY_INPUT_DIR="$(readlink -f "$LEGACY_INPUT_DIR")"
[[ -d "$LEGACY_INPUT_DIR" ]] || { echo "[ERROR] legacy input dir not found: $LEGACY_INPUT_DIR" >&2; exit 1; }
[[ -x "$ORCA_CMD" ]] || { echo "[ERROR] ORCA executable not found or not executable: $ORCA_CMD" >&2; exit 1; }

###################### PATH SETUP ################################

PROJECT_DIR="${PROJECT_DATE}_${PROJECT_NAME}"
ECD_DIR="${CALC_DATE}_ECD_calculation"
INPUT_DIR="/hdd/${PROJECT_DIR}/data/${ECD_DIR}"
SRC_DIR="/hdd/${PROJECT_DIR}/src"
SCRIPT_DIR="/hdd/${PROJECT_DIR}/scripts"
POSTPROCESS_PY="${SRC_DIR}/orca_ecd_postprocess.py"
ECD_PLOT_R="${SCRIPT_DIR}/ecd_plot.R"

echo "[INFO] PROJECT_DATE=$PROJECT_DATE"
echo "[INFO] CALC_DATE=$CALC_DATE"
echo "[INFO] PROJECT_NAME=$PROJECT_NAME"
echo "[INFO] LEGACY_INPUT_DIR=$LEGACY_INPUT_DIR"
echo "[INFO] SOLVENT=$SOLVENT"
echo "[INFO] CHARGE=$CHARGE"
echo "[INFO] MULT=$MULT"
echo "[INFO] CREST_MODE=$CREST_MODE"
echo "[INFO] EWIN_INPUT=$EWIN_INPUT"
echo "[INFO] ORCA_CMD=$ORCA_CMD"
echo "[INFO] MAX_JOBS=$MAX_JOBS"

cd /hdd
mkdir -p "${PROJECT_DIR}"/{src,scripts,data,results,docs,paper}
touch "${PROJECT_DIR}"/{README.md,.gitignore,LICENSE,requirements.txt}
mkdir -p "${INPUT_DIR}"

echo "[INFO] PROJECT_DIR=${PROJECT_DIR}"
echo "[INFO] ECD_DIR=${ECD_DIR}"
echo "[INFO] INPUT_DIR=${INPUT_DIR}"

###################### COPY INPUT FILES ################################

if compgen -G "${LEGACY_INPUT_DIR}/${PROJECT_NAME}*.mol2" > /dev/null; then
  cp -f "${LEGACY_INPUT_DIR}"/"${PROJECT_NAME}"*.mol2 "${INPUT_DIR}/"
else
  echo "[WARN] no mol2 files found: ${LEGACY_INPUT_DIR}/${PROJECT_NAME}*.mol2"
fi

if compgen -G "${LEGACY_INPUT_DIR}/${PROJECT_NAME}*.csv" > /dev/null; then
  cp -f "${LEGACY_INPUT_DIR}"/"${PROJECT_NAME}"*.csv "${INPUT_DIR}/"
else
  echo "[WARN] no csv files found: ${LEGACY_INPUT_DIR}/${PROJECT_NAME}*.csv"
fi

###################### WRITE HELPER SCRIPT: run_crest.sh ################################

cat > "${SCRIPT_DIR}/run_crest.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

INPUT=""
NAME=""
PROJECT_DIR=""
SOLVENT=""
CHARGE="0"
MULT="1"
CREST_MODE="precise"
EWIN_INPUT="20"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT="$2"
      shift 2
      ;;
    --name)
      NAME="$2"
      shift 2
      ;;
    --project-dir)
      PROJECT_DIR="$2"
      shift 2
      ;;
    --solvent)
      SOLVENT="$2"
      shift 2
      ;;
    --charge)
      CHARGE="$2"
      shift 2
      ;;
    --mult)
      MULT="$2"
      shift 2
      ;;
    --crest-mode)
      CREST_MODE="$2"
      shift 2
      ;;
    --ewin-input)
      EWIN_INPUT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: bash $0 --input <input_file> --name <job_name> --project-dir <project_dir> --solvent <solvent_name> [--charge 0] [--mult 1] [--crest-mode precise] [--ewin-input 20]"
      exit 1
      ;;
  esac
done

if [[ -z "$INPUT" || -z "$NAME" || -z "$PROJECT_DIR" || -z "$SOLVENT" ]]; then
  echo "Error: --input, --name, --project-dir, and --solvent are required."
  exit 1
fi

PY_SCRIPT="/hdd/${PROJECT_DIR}/src/conformer_search_crest3.py"

if [[ ! -f "$PY_SCRIPT" ]]; then
  echo "Error: Python script not found: $PY_SCRIPT"
  exit 1
fi

python3 "$PY_SCRIPT" \
  --input "$INPUT" \
  --name "$NAME" \
  --charge "$CHARGE" \
  --mult "$MULT" \
  --solvent "$SOLVENT" \
  --crest-mode "$CREST_MODE" \
  --ewin-input "$EWIN_INPUT"

echo "crest finished"
date
EOF
chmod +x "${SCRIPT_DIR}/run_crest.sh"

###################### WRITE PYTHON: conformer_search_crest3.py ################################

cat > "${SRC_DIR}/conformer_search_crest3.py" <<'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os, sys, json, argparse, subprocess, shutil, re, math
from pathlib import Path
from typing import List, Tuple, Dict, Optional

from rdkit import Chem
from rdkit.Chem import AllChem
from rdkit.Chem import rdmolfiles, rdmolops
from rdkit.Chem.rdmolops import SanitizeFlags

import numpy as np
import pandas as pd

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

print("pipeline : conformer search via CREST")

FIXED_SEED = 2025

def mkdir(p: Path):
    p.mkdir(parents=True, exist_ok=True)

def write_text(path: Path, s: str):
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    path.write_text(s, encoding="utf-8")

def run(cmd: list, cwd: Path = None) -> int:
    print(">", " ".join(cmd))
    return subprocess.call(cmd, cwd=str(cwd) if cwd else None)

def run_with_env(cmd: str, cwd: Path, threads1: bool = True) -> int:
    env = os.environ.copy()
    if threads1:
        env.setdefault("OPENBLAS_NUM_THREADS", "1")
        env.setdefault("OMP_NUM_THREADS", "1")
        env.setdefault("MKL_NUM_THREADS", "1")
        env.setdefault("NUMEXPR_NUM_THREADS", "1")
    print(">", cmd)
    return subprocess.call(["bash", "-lc", cmd], cwd=str(cwd) if cwd else None, env=env)

def detect_crest_major() -> Optional[int]:
    probes = [["crest", "--version"], ["crest", "-h"], ["crest", "--help"]]
    for p in probes:
        try:
            out = subprocess.check_output(p, stderr=subprocess.STDOUT, text=True)
        except Exception:
            continue
        m = re.search(r"CREST[^\n]*?(\d+)\.(\d+)\.(\d+)", out)
        if m:
            return int(m.group(1))
    return None

def _post_sanitize(mol: Chem.Mol) -> Chem.Mol:
    if mol is None:
        return None
    try:
        rdmolops.SanitizeMol(mol, sanitizeOps=SanitizeFlags.SANITIZE_ALL)
    except Exception:
        rdmolops.SanitizeMol(
            mol,
            sanitizeOps=(
                SanitizeFlags.SANITIZE_PROPERTIES
                | SanitizeFlags.SANITIZE_SYMMRINGS
                | SanitizeFlags.SANITIZE_KEKULIZE
            ),
        )
    Chem.AssignStereochemistry(mol, cleanIt=True, force=True)
    need_3d = (mol.GetNumConformers() == 0) or (not mol.GetConformer().Is3D())
    mol = Chem.AddHs(mol, addCoords=True)
    if need_3d:
        try:
            params = (
                AllChem.ETKDGv3()
                if hasattr(AllChem, "ETKDGv3")
                else (AllChem.ETKDGv2() if hasattr(AllChem, "ETKDGv2") else AllChem.ETKDG())
            )
            params.enforceChirality = True
            AllChem.EmbedMolecule(mol, params)
            try:
                AllChem.MMFFOptimizeMolecule(mol)
            except Exception:
                pass
        except Exception:
            pass
    return mol

def _read_mol2(path: Path) -> Optional[Chem.Mol]:
    try:
        mol = rdmolfiles.MolFromMol2File(str(path), sanitize=True, removeHs=False)
        if mol:
            return _post_sanitize(mol)
    except Exception:
        pass
    try:
        mol = rdmolfiles.MolFromMol2File(str(path), sanitize=False, removeHs=False)
        if mol:
            return _post_sanitize(mol)
    except Exception:
        pass
    return None

def _read_sdf_first(path: Path) -> Optional[Chem.Mol]:
    try:
        suppl = Chem.SDMolSupplier(str(path), removeHs=False, sanitize=False)
        mol = next((m for m in suppl if m is not None), None)
        if mol:
            return _post_sanitize(mol)
    except Exception:
        pass
    return None

def _read_molfile(path: Path) -> Optional[Chem.Mol]:
    try:
        mol = rdmolfiles.MolFromMolFile(str(path), sanitize=False, removeHs=False)
        if mol:
            return _post_sanitize(mol)
    except Exception:
        pass
    return None

def _read_smiles(s: str) -> Optional[Chem.Mol]:
    try:
        mol = Chem.MolFromSmiles(s, sanitize=True)
        if not mol:
            return None
        mol = Chem.AddHs(mol)
        try:
            params = (
                AllChem.ETKDGv3()
                if hasattr(AllChem, "ETKDGv3")
                else (AllChem.ETKDGv2() if hasattr(AllChem, "ETKDGv2") else AllChem.ETKDG())
            )
            params.enforceChirality = True
            AllChem.EmbedMolecule(mol, params)
            try:
                AllChem.MMFFOptimizeMolecule(mol)
            except Exception:
                pass
        except Exception:
            pass
        return _post_sanitize(mol)
    except Exception:
        return None

def smiles_or_sdf_to_mol(input_path_or_smiles: str) -> Chem.Mol:
    p = Path(input_path_or_smiles)
    if p.exists():
        ext = p.suffix.lower()
        if ext in [".sdf", ".sd"]:
            mol = _read_sdf_first(p)
        elif ext in [".mol"]:
            mol = _read_molfile(p)
        elif ext == ".mol2":
            mol = _read_mol2(p)
        else:
            raise ValueError("If giving a file, use .sdf/.mol/.mol2; otherwise pass a SMILES string.")
        if mol is None:
            raise ValueError(f"failed to read molecule from {p} (unsupported/corrupted file)")
        return mol
    mol = _read_smiles(input_path_or_smiles)
    if mol is None:
        raise ValueError(f"Could not parse SMILES: {input_path_or_smiles}")
    return mol

def _mmff_or_uff_props(mol: Chem.Mol):
    mmffp = AllChem.MMFFGetMoleculeProperties(mol, mmffVariant="MMFF94s")
    if mmffp is not None:
        return ("MMFF", mmffp)
    return ("UFF", None)

def _make_etkdg_params():
    for ctor in ("ETKDGv3", "ETKDGv2", "ETKDG"):
        if hasattr(AllChem, ctor):
            params = getattr(AllChem, ctor)()
            break
    else:
        params = AllChem.EmbedParameters()

    def set_if_has(obj, name, value):
        if hasattr(obj, name):
            setattr(obj, name, value)

    set_if_has(params, "pruneRmsThresh", 0.0)
    set_if_has(params, "useSmallRingTorsions", True)
    set_if_has(params, "useBasicKnowledge", True)
    set_if_has(params, "enforceChirality", True)
    set_if_has(params, "maxAttempts", 500)
    set_if_has(params, "maxIterations", 500)
    return params

def quick_seed_xyz(mol: Chem.Mol, charge: int, mult: int, seed: int, path: Path):
    params = _make_etkdg_params()
    if hasattr(params, "randomSeed"):
        params.randomSeed = seed
    if mol.GetNumAtoms() == Chem.RemoveHs(mol).GetNumAtoms():
        mol = Chem.AddHs(mol)
    cids = AllChem.EmbedMultipleConfs(mol, numConfs=20, params=params)
    if not cids:
        raise RuntimeError("Seed conformer embedding failed.")
    ff_name, mmffp = _mmff_or_uff_props(mol)
    if ff_name == "MMFF":
        AllChem.MMFFOptimizeMoleculeConfs(mol, numThreads=0, maxIters=500, mmffVariant="MMFF94s")
    else:
        AllChem.UFFOptimizeMoleculeConfs(mol, numThreads=0, maxIters=500)
    best_cid, best_e = None, 1e99
    for cid in cids:
        ff = (
            AllChem.MMFFGetMoleculeForceField(mol, mmffp, confId=cid)
            if ff_name == "MMFF"
            else AllChem.UFFGetMoleculeForceField(mol, confId=cid)
        )
        e = float(ff.CalcEnergy())
        if e < best_e:
            best_e, best_cid = e, cid
    conf = mol.GetConformer(best_cid)
    lines = []
    for i, atom in enumerate(mol.GetAtoms()):
        pos = conf.GetAtomPosition(i)
        lines.append(f"{atom.GetSymbol():<2} {pos.x: .6f} {pos.y: .6f} {pos.z: .6f}")
    xyz = f"{mol.GetNumAtoms()}\ncharge={charge} mult={mult} conf={best_cid}\n" + "\n".join(lines) + "\n"
    write_text(path, xyz)

def split_multiframe_xyz(xyz_path: Path) -> List[List[str]]:
    lines = xyz_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    frames: List[List[str]] = []
    i, n = 0, len(lines)
    while i < n:
        try:
            nat = int(lines[i].strip())
        except Exception:
            i += 1
            continue
        if i + 1 + nat >= n:
            break
        frame = lines[i : i + 2 + nat]
        frames.append(frame)
        i += 2 + nat
    return frames

def write_single_xyz(frame_lines: List[str], out_path: Path):
    content = "\n".join(frame_lines)
    if not content.endswith("\n"):
        content += "\n"
    write_text(out_path, content)

def crest_preset(mode: str, solvent: str) -> Tuple[str, str, str]:
    opt = ""
    if not mode:
        return ("", "", "")
    base = "-cbonds -seed 2025 -niceprint"
    if mode == "fast":
        extra = f"-ewin 8  -rthr 0.10 {base}"
        model = "gbsa"
    elif mode == "precise":
        extra = f"-ewin 12 -rthr 0.07 {base}"
        model = "gbsa"
    elif mode == "ultra":
        extra = f"-ewin 20 -rthr 0.05 {base}"
        model = "alpb"
    else:
        return ("", "", "")
    return (opt, extra, model)

def crest_stage(
    outroot: Path,
    charge: int,
    mult: int,
    solvent: str,
    mdopt_xyz: Optional[str],
    seed_xyz: Optional[Path],
    gfn_level: int,
    opt_level: str,
    extra_flags: str,
    solvent_model: str = "g",
) -> Path:
    stage_dir = outroot / "stage0_crest"
    mkdir(stage_dir)
    traj_xyz = stage_dir / "traj.xyz"

    if mdopt_xyz:
        src = Path(mdopt_xyz).expanduser().resolve()
        if not src.exists():
            raise FileNotFoundError(f"--crest-mdopt not found: {src}")
        if src.resolve() != traj_xyz.resolve():
            shutil.copyfile(src, traj_xyz)
        else:
            print("Note: using existing traj.xyz (from --crest-mdopt).")
    elif seed_xyz and seed_xyz.exists():
        src = Path(seed_xyz).resolve()
        if src.resolve() != traj_xyz.resolve():
            shutil.copyfile(src, traj_xyz)
        else:
            print("Note: using existing traj.xyz (seed already at stage0_crest).")
    else:
        raise RuntimeError("No traj.xyz provided for CREST.")

    uhf = max(0, mult - 1)
    s = (solvent or "").strip().lower()
    major = detect_crest_major()

    if s:
        if (solvent_model or "").lower() == "alpb":
            solv_flag = f'--alpb "{s}"' if (major and major >= 3) else f'-alpb "{s}"'
        else:
            solv_flag = f'--gbsa "{s}"' if (major and major >= 3) else f'-g "{s}"'
    else:
        solv_flag = ""

    opt_piece = f"-opt {opt_level}" if (opt_level and str(opt_level).lower() not in ("", "none", "noopt", "off")) else ""

    extra = (extra_flags or "").strip()
    if extra:
        extra = re.sub(r'(?:^|\s)-cinp(?:\s+\S+)?', '', extra)
        extra = re.sub(r'(?:^|\s)-T\s+\S+', '', extra)
        extra = re.sub(r'\s+', ' ', extra).strip()
    if " -seed " not in f" {extra} ":
        extra = (extra + f" -seed {FIXED_SEED}").strip()

    existing_ens = outroot / "ensemble.xyz"
    if existing_ens.exists() and existing_ens.stat().st_size > 0:
        print("Found ensemble.xyz → skip CREST stage and reuse.")
        return existing_ens

    base_cmd = (
        f'crest -mdopt traj.xyz -gfn{gfn_level} {opt_piece} {solv_flag} -chrg {charge} -uhf {uhf} -niceprint {extra}'
        if mdopt_xyz
        else f'crest traj.xyz -gfn{gfn_level} {opt_piece} {solv_flag} -chrg {charge} -uhf {uhf} -niceprint {extra}'
    )

    code = run_with_env(base_cmd + " | tee -a ./out.log", cwd=stage_dir, threads1=True)

    if code != 0 and (major is not None and major >= 3):
        print("[info] CREST failed; retrying with --legacy …")
        code = run_with_env(base_cmd + " --legacy | tee -a ./out.log", cwd=stage_dir, threads1=True)

    if code != 0 and (major is not None and major >= 3):
        print("[info] CREST still failed; last retry toggling legacy flag …")
        alt = (base_cmd + " | tee -a ./out.log") if ("--legacy" in base_cmd) else (base_cmd + " --legacy | tee -a ./out.log")
        code = run_with_env(alt, cwd=stage_dir, threads1=True)

    if code != 0:
        raise RuntimeError("CREST run failed; see stage0_crest/out.log")

    candidate_names = [
        "crest_ensemble.xyz",
        "crest_conformers.xyz",
        "crest_best.xyz",
        "ensemble.xyz",
        "conformers.xyz",
        "best.xyz",
        "rotamers.xyz",
        "crestopt.xyz",
        "crest.en",
        "final_ensemble.xyz",
    ]
    for name in candidate_names:
        p = stage_dir / name
        if p.exists() and p.stat().st_size > 0:
            dest = outroot / "ensemble.xyz"
            shutil.copyfile(p, dest)
            return dest

    maybe_trj = stage_dir / "crest_conformers.trj"
    if maybe_trj.exists() and maybe_trj.stat().st_size > 0:
        dest = outroot / "ensemble.xyz"
        shutil.copyfile(maybe_trj, dest)
        return dest

    raise FileNotFoundError("CREST outputs not found (ensemble/conformers/best).")

def check_xyz_sane(xyz_path: Path):
    if not xyz_path.exists():
        raise FileNotFoundError(f"Missing geometry file: {xyz_path}")
    txt = xyz_path.read_text(encoding="utf-8", errors="ignore").replace("\r\n", "\n").replace("\r", "\n")
    lines = txt.split("\n")
    try:
        nat = int(lines[0].strip())
    except Exception:
        raise ValueError(f"Bad XYZ header (N atoms not int): {xyz_path}")
    coord_lines = [l for l in lines[2:] if l.strip() != ""]
    if len(coord_lines) < nat:
        raise ValueError(f"XYZ atom count mismatch in {xyz_path}: need {nat}, got {len(coord_lines)}")

def parse_crest_energies_kcal(path: Path) -> List[float]:
    if not path.exists():
        return []
    energies = []
    lines = [l.strip() for l in path.read_text(errors="ignore").splitlines() if l.strip()]
    for l in lines:
        if l.lower().startswith("idx") or l.startswith("#"):
            continue
        cols = l.split()
        if len(cols) >= 2:
            try:
                energies.append(float(cols[1]))
            except Exception:
                pass
    return energies

def plot_conformer_energy_hist(energies_kcal: List[float], outdir: Path, ewin_input: float):
    if not energies_kcal:
        print("[warn] no energies for histogram.")
        return
    vals = [e for e in energies_kcal if np.isfinite(e)]
    if not vals:
        print("[warn] energies invalid for histogram.")
        return

    bins = np.arange(0, max(20, int(math.ceil(max(vals))) + 1), 1)
    plt.figure(figsize=(7, 4.5), dpi=160)
    n, bins, _ = plt.hist(vals, bins=bins, edgecolor="black")
    for i, cnt in enumerate(n):
        if cnt > 0:
            plt.text(bins[i] + 0.5, cnt + 0.05, f"{int(cnt)}", ha="center", va="bottom", fontsize=8)
    plt.axvline(ewin_input, linestyle="--", label=f"ewin-input={ewin_input:g} kcal/mol")
    plt.xlabel("Relative Energy (kcal/mol)")
    plt.ylabel("Number of Conformers")
    plt.title("CREST Conformer Energy Distribution")
    plt.legend(frameon=False)
    plt.tight_layout()
    out_png = outdir / "energy_distribution.png"
    plt.savefig(out_png)
    print(f"[plot] wrote {out_png}")

def parse_args():
    ap = argparse.ArgumentParser(description="CREST-only conformer search pipeline")
    ap.add_argument("--input", required=True, help="SMILES or .sdf/.mol/.mol2")
    ap.add_argument("--name", default="job", help="output directory name")
    ap.add_argument("--charge", type=int, default=0)
    ap.add_argument("--mult", type=int, default=1)
    ap.add_argument("--solvent", default="", help='solvent for CREST (gbsa/alpb)')
    ap.add_argument("--crest-mode", choices=["fast", "precise", "ultra"], default=None)
    ap.add_argument("--no-crest", action="store_true", help="skip CREST and only emit a seed conf_001")
    ap.add_argument("--crest-mdopt", default="", help="existing traj.xyz for crest -mdopt")
    ap.add_argument("--crest-gfn", type=int, default=2, choices=[1, 2])
    ap.add_argument("--crest-opt", default="normal")
    ap.add_argument("--crest-extra", default="")
    ap.add_argument("--ewin-input", type=float, default=20.0, help="kcal/mol; only emit conformers within this cutoff")
    return ap.parse_args()

def main():
    args = parse_args()
    outroot = Path(args.name).resolve()
    mkdir(outroot)

    mol = smiles_or_sdf_to_mol(args.input)
    if mol.GetNumConformers() == 0:
        mol = Chem.AddHs(mol)

    frames: List[List[str]] = []
    ensemble_path = outroot / "ensemble.xyz"
    crest_energy_file = outroot / "stage0_crest" / "crest.energies"

    if not args.no_crest:
        if ensemble_path.exists() and ensemble_path.stat().st_size > 0:
            print("Found ensemble.xyz → skip CREST and reuse.")
            frames = split_multiframe_xyz(ensemble_path)
        else:
            preset_opt, preset_extra, preset_model = crest_preset(args.crest_mode, args.solvent)
            if args.crest_mode:
                use_opt = preset_opt
            else:
                use_opt = args.crest_opt if str(args.crest_opt).lower() not in ("", "none", "noopt", "off") else ""
            use_extra = (preset_extra + (" " + args.crest_extra.strip() if args.crest_extra.strip() else "")).strip()
            use_model = preset_model if preset_model else "g"

            stage0 = outroot / "stage0_crest"
            mkdir(stage0)
            seed_xyz = None
            if not args.crest_mdopt:
                seed_xyz = stage0 / "traj.xyz"
                print("Preparing seed traj.xyz for CREST (ETKDGv3 + MM minimization)…")
                quick_seed_xyz(Chem.Mol(mol), args.charge, args.mult, FIXED_SEED, seed_xyz)

            ensemble_xyz = crest_stage(
                outroot=outroot,
                charge=args.charge,
                mult=args.mult,
                solvent=args.solvent,
                mdopt_xyz=(args.crest_mdopt if args.crest_mdopt else None),
                seed_xyz=seed_xyz,
                gfn_level=args.crest_gfn,
                opt_level=use_opt,
                extra_flags=use_extra,
                solvent_model=use_model,
            )
            frames = split_multiframe_xyz(ensemble_xyz)

        if not frames:
            raise RuntimeError("No frames parsed from CREST ensemble.xyz")
        print(f"CREST frames: {len(frames)}")
    else:
        print("WARN: --no-crest given. This disables rigorous conformer search.")

    energies_kcal = parse_crest_energies_kcal(crest_energy_file)
    if crest_energy_file.exists():
        try:
            shutil.copyfile(crest_energy_file, outroot / "crest.energies")
        except Exception:
            pass

    if energies_kcal:
        if len(energies_kcal) < len(frames):
            print(f"[warn] crest.energies entries ({len(energies_kcal)}) < frames ({len(frames)}). Will truncate frames to energies length.")
            frames = frames[:len(energies_kcal)]
        plot_conformer_energy_hist(energies_kcal, outroot, args.ewin_input)
    else:
        print("[warn] missing/empty crest.energies → no histogram; will include all frames")

    kept_info = []
    selection_rows = []

    if frames:
        print("Distributing CREST frames into conf_* folders…")
        for i, frame in enumerate(frames, start=1):
            e_rel = energies_kcal[i - 1] if (i - 1) < len(energies_kcal) else float("nan")
            within_input = (np.isfinite(e_rel) and (e_rel <= args.ewin_input)) or (not energies_kcal)

            if not within_input:
                continue

            conf_dir = outroot / f"conf_{i:03d}"
            mkdir(conf_dir)
            xyz_file = conf_dir / "conf.xyz"
            write_single_xyz(frame, xyz_file)
            check_xyz_sane(xyz_file)

            kept_info.append((conf_dir, i))
            selection_rows.append(
                {
                    "conf": f"conf_{i:03d}",
                    "Erel_kcal": e_rel if np.isfinite(e_rel) else "",
                    "within_input": int(within_input),
                }
            )

        if not kept_info:
            print("[warn] no conformers within --ewin-input; keep lowest-energy one as fallback.")
            conf_dir = outroot / "conf_001"
            mkdir(conf_dir)
            write_single_xyz(frames[0], conf_dir / "conf.xyz")
            kept_info.append((conf_dir, 1))
            selection_rows.append(
                {
                    "conf": "conf_001",
                    "Erel_kcal": energies_kcal[0] if energies_kcal else "",
                    "within_input": 1,
                }
            )

        try:
            pd.DataFrame(selection_rows).to_csv(outroot / "conformer_selection.csv", index=False)
        except Exception:
            pass

        tab = [{"rank": i, "source": "CREST", "idx": i} for _, i in kept_info]
        write_text(outroot / "conformers.json", json.dumps(tab, indent=2))
    else:
        conf_dir = outroot / "conf_001"
        mkdir(conf_dir)
        seed_fallback = outroot / "stage0_crest" / "traj.xyz"
        if not seed_fallback.exists():
            seed_fallback = outroot / "seed.xyz"
            quick_seed_xyz(Chem.Mol(mol), args.charge, args.mult, FIXED_SEED, seed_fallback)
        shutil.copyfile(seed_fallback, conf_dir / "conf.xyz")
        check_xyz_sane(conf_dir / "conf.xyz")
        kept_info.append((conf_dir, 1))
        write_text(outroot / "conformers.json", json.dumps([{"rank": 1, "source": "seed-only"}], indent=2))

    print(f"\\nDone: CREST-only outputs written in {outroot}")
    print("   • Stage 0: CREST rigorous search → ensemble.xyz → conf_###/conf.xyz")
    print(f"   • Selection: inputs <= {args.ewin_input:g} kcal/mol")
    print("   • Gaussian input generation / run.sh / ECD postprocess removed")

if __name__ == "__main__":
    main()
EOF
chmod +x "${SRC_DIR}/conformer_search_crest3.py"

###################### WRITE PYTHON: orca_ecd_postprocess.py ################################

cat > "${POSTPROCESS_PY}" <<'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Post-process ORCA TD-DFT UV/ECD results with Boltzmann weighting.

功能：
1. 在 --root 指定目录下自动识别 conf_*/ 子目录。
2. 默认优先从每个构象的 single_point.log 中提取 FINAL SINGLE POINT ENERGY
   作为 Boltzmann 权重来源。
3. 若 single_point.log 不存在或解析失败，则回退到 opt_freq.log：
   - 优先读取 Total Gibbs free energy
   - 若没有，则回退到 FINAL SINGLE POINT ENERGY
4. 从 ecd.log 中解析：
   - UV：ABSORPTION SPECTRUM VIA TRANSITION ELECTRIC DIPOLE MOMENTS 表
   - ECD：CD SPECTRUM VIA TRANSITION ELECTRIC DIPOLE MOMENTS 表
   读取激发能量 (eV) + fosc / R(电偶极)
5. 在统一能量网格上做 Gaussian 展宽，生成：
   - 所有构象 UV/ECD 曲线 + Boltzmann 加权曲线（PNG 图）
   - UV/ECD 的 nm 轴 TSV，每个构象一列，再加一列 Boltzmann 加权总谱
   - 权重表和 Boltzmann 总谱 (eV / nm)

注意：
- 展宽的 “Gaussian” 指的是谱线的高斯线形，与 Gaussian 软件无关。
- 所有谱线强度都是相对单位，只在构象之间互相可比。
"""

import os
import argparse
import math
from typing import Tuple, List, Dict

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# 物理常数
KB_HARTREE_PER_K = 3.166811563e-6   # k_B in Hartree/K
EV_TO_NM_FACTOR = 1239.84193        # lambda[nm] = 1239.84193 / E[eV]
HARTREE_TO_KJMOL = 2625.49962


def parse_args():
    parser = argparse.ArgumentParser(
        description="Post-process ORCA UV/ECD results with Boltzmann weighting."
    )
    parser.add_argument(
        "--root",
        type=str,
        default=".",
        help="根目录（包含多个 conf_XXX 子目录），默认当前目录",
    )
    parser.add_argument(
        "--temperature",
        type=float,
        default=298.15,
        help="玻尔兹曼权重温度 (K)，默认 298.15",
    )
    parser.add_argument(
        "--fwhm",
        type=float,
        default=0.30,
        help="谱线展宽 FWHM（单位 eV），默认 0.30",
    )
    parser.add_argument(
        "--emin",
        type=float,
        default=2.48,
        help="能量网格最小值 (eV)，默认 2.48（约 500 nm）",
    )
    parser.add_argument(
        "--emax",
        type=float,
        default=6.90,
        help="能量网格最大值 (eV)，默认 6.90（约 180 nm）",
    )
    parser.add_argument(
        "--estep",
        type=float,
        default=0.01,
        help="能量网格步长 (eV)，默认 0.01",
    )
    parser.add_argument(
        "--max-states",
        type=int,
        default=None,
        help="每个构象最多读取的激发态数，默认不限制",
    )
    parser.add_argument(
        "--prefix",
        type=str,
        default="ecd",
        help="输出文件前缀，默认 'ecd'",
    )
    parser.add_argument(
        "--energy-source",
        choices=["single_point", "opt_freq", "auto"],
        default="single_point",
        help=(
            "Boltzmann 权重能量来源："
            "single_point=优先 single_point.log；"
            "opt_freq=只用 opt_freq.log；"
            "auto=single_point 优先，失败再回退 opt_freq。"
            "默认 single_point"
        ),
    )
    return parser.parse_args()


def is_float_token(tok: str) -> bool:
    try:
        float(tok)
        return True
    except ValueError:
        return False


def scan_last_float_in_line(line: str):
    for tok in reversed(line.replace(":", " ").split()):
        try:
            return float(tok)
        except ValueError:
            continue
    return None


def find_conf_dirs(root: str):
    confs = []
    for name in sorted(os.listdir(root)):
        path = os.path.join(root, name)
        if os.path.isdir(path) and name.startswith("conf_"):
            confs.append((name, path))
    if not confs:
        raise RuntimeError(f"在 {root} 下没有发现任何 conf_* 目录")
    return confs


def parse_energy_from_single_point(log_path: str) -> float:
    """
    从 single_point.log 中读取 FINAL SINGLE POINT ENERGY
    """
    if not os.path.isfile(log_path):
        raise FileNotFoundError(f"未找到 single_point log：{log_path}")

    energy = None
    with open(log_path, "r", errors="ignore") as f:
        for line in f:
            if "FINAL SINGLE POINT ENERGY" in line:
                val = scan_last_float_in_line(line)
                if val is not None:
                    energy = val

    if energy is None:
        raise RuntimeError(
            f"在 {log_path} 中没有找到 'FINAL SINGLE POINT ENERGY'"
        )

    return energy


def parse_energy_from_optfreq(log_path: str) -> float:
    """
    从 opt_freq.log 中读取：
    1) 优先 Total Gibbs free energy
    2) 若没有，则回退到 FINAL SINGLE POINT ENERGY
    """
    if not os.path.isfile(log_path):
        raise FileNotFoundError(f"未找到 opt_freq log：{log_path}")

    with open(log_path, "r", errors="ignore") as f:
        lines = f.readlines()

    energy = None

    for line in lines:
        if "Total Gibbs free energy" in line:
            val = scan_last_float_in_line(line)
            if val is not None:
                energy = val

    if energy is not None:
        return energy

    for line in lines:
        if "FINAL SINGLE POINT ENERGY" in line:
            val = scan_last_float_in_line(line)
            if val is not None:
                energy = val

    if energy is None:
        raise RuntimeError(
            f"在 {log_path} 中既没有找到 'Total Gibbs free energy'，也没有找到 "
            f"'FINAL SINGLE POINT ENERGY'"
        )

    return energy


def parse_conf_energy(conf_dir: str, energy_source: str = "single_point") -> Tuple[float, str]:
    """
    返回：
      energy_hartree, source_label
    """
    sp_log = os.path.join(conf_dir, "single_point.log")
    opt_log = os.path.join(conf_dir, "opt_freq.log")

    if energy_source == "single_point":
        energy = parse_energy_from_single_point(sp_log)
        return energy, "single_point"

    if energy_source == "opt_freq":
        energy = parse_energy_from_optfreq(opt_log)
        return energy, "opt_freq"

    # auto
    try:
        energy = parse_energy_from_single_point(sp_log)
        return energy, "single_point"
    except Exception:
        energy = parse_energy_from_optfreq(opt_log)
        return energy, "opt_freq"


def parse_orca_spectrum_from_log(
    log_path: str,
    kind: str,
    max_states: int = None,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    从 ecd.log 中解析 UV/ECD 谱线：
    kind = 'UV'  => ABSORPTION SPECTRUM VIA TRANSITION ELECTRIC DIPOLE MOMENTS
    kind = 'ECD' => CD SPECTRUM VIA TRANSITION ELECTRIC DIPOLE MOMENTS

    表格通用格式：
        Transition ...  Energy(eV)  Energy(cm-1)  Wavelength(nm)  fosc/R  TX/TY/TZ

    假设：
        - 行里第一个能转成 float 的 token 是能量 (eV)
        - 再往后第 3 个 float 是 fosc 或 R
    """
    if not os.path.isfile(log_path):
        raise FileNotFoundError(f"未找到 ORCA log 文件：{log_path}")

    if kind.upper() == "UV":
        marker = "ABSORPTION SPECTRUM VIA TRANSITION ELECTRIC DIPOLE MOMENTS"
    elif kind.upper() == "ECD":
        marker = "CD SPECTRUM VIA TRANSITION ELECTRIC DIPOLE MOMENTS"
    else:
        raise ValueError(f"未知 kind={kind}，只能是 'UV' 或 'ECD'")

    with open(log_path, "r", errors="ignore") as f:
        lines = f.readlines()

    energies: List[float] = []
    intens: List[float] = []

    n = len(lines)
    idx = 0
    found_marker = False

    while idx < n:
        line = lines[idx]
        if marker in line:
            found_marker = True
            break
        idx += 1

    if not found_marker:
        raise RuntimeError(f"在 {log_path} 中没有找到光谱数据块：{marker}")

    idx += 1
    while idx < n and "Transition" not in lines[idx]:
        idx += 1

    if idx >= n:
        raise RuntimeError(
            f"在 {log_path} 中找到了 '{marker}'，但没有找到表头 'Transition ...'"
        )

    # 跳过表头两行 + 分隔线一行
    idx += 3

    count = 0
    while idx < n:
        l = lines[idx].strip()
        if not l:
            break
        if l.startswith("-"):
            break
        if "->" not in l:
            break

        parts = l.split()

        first_float_idx = None
        for j, tok in enumerate(parts):
            if is_float_token(tok):
                first_float_idx = j
                break

        if first_float_idx is None:
            break
        if len(parts) < first_float_idx + 4:
            break

        try:
            e_eV = float(parts[first_float_idx])
            inten = float(parts[first_float_idx + 3])
        except ValueError:
            break

        energies.append(e_eV)
        intens.append(inten)
        count += 1

        if max_states is not None and count >= max_states:
            break

        idx += 1

    if len(energies) == 0:
        raise RuntimeError(f"在 {log_path} 中没有成功解析出光谱数据块：{marker}")

    return np.array(energies, dtype=float), np.array(intens, dtype=float)


def gaussian_broadening(
    E_grid: np.ndarray,
    E_lines: np.ndarray,
    I_lines: np.ndarray,
    fwhm_eV: float,
) -> np.ndarray:
    if len(E_lines) == 0:
        return np.zeros_like(E_grid)

    sigma = fwhm_eV / (2.0 * math.sqrt(2.0 * math.log(2.0)))
    intens = np.zeros_like(E_grid)

    for Ei, Ii in zip(E_lines, I_lines):
        intens += Ii * np.exp(-0.5 * ((E_grid - Ei) / sigma) ** 2)

    return intens


def build_energy_grid(emin: float, emax: float, estep: float) -> np.ndarray:
    n_pts = int(round((emax - emin) / estep)) + 1
    return np.linspace(emin, emax, n_pts)


def energy_to_wavelength(E_eV_array: np.ndarray):
    lam = EV_TO_NM_FACTOR / E_eV_array
    order = np.argsort(lam)
    return lam[order], order


def main():
    args = parse_args()

    root = os.path.abspath(args.root)
    confs = find_conf_dirs(root)

    print(f"[INFO] root = {root}")
    print(f"[INFO] 发现 {len(confs)} 个构象目录：")
    for name, _ in confs:
        print(f"       - {name}")

    spectra_dir = root
    plots_dir = root

    conf_energies: Dict[str, float] = {}
    conf_energy_source: Dict[str, str] = {}
    uv_E: Dict[str, np.ndarray] = {}
    uv_I: Dict[str, np.ndarray] = {}
    ecd_E: Dict[str, np.ndarray] = {}
    ecd_R: Dict[str, np.ndarray] = {}

    for name, path in confs:
        ecd_log_path = os.path.join(path, "ecd.log")

        # 能量：默认 single_point 优先
        energy, source_label = parse_conf_energy(path, args.energy_source)
        conf_energies[name] = energy
        conf_energy_source[name] = source_label

        # UV
        try:
            E_uv, I_uv = parse_orca_spectrum_from_log(
                ecd_log_path, kind="UV", max_states=args.max_states
            )
        except Exception as e:
            print(f"[WARN] {name}: 解析 UV 失败：{e}")
            E_uv = np.array([], dtype=float)
            I_uv = np.array([], dtype=float)
        uv_E[name] = E_uv
        uv_I[name] = I_uv

        # ECD
        try:
            E_ecd, R_ecd = parse_orca_spectrum_from_log(
                ecd_log_path, kind="ECD", max_states=args.max_states
            )
        except Exception as e:
            print(f"[WARN] {name}: 解析 ECD 失败：{e}")
            E_ecd = np.array([], dtype=float)
            R_ecd = np.array([], dtype=float)
        ecd_E[name] = E_ecd
        ecd_R[name] = R_ecd

        print(
            f"[INFO] {name}: E = {energy:.8f} Eh ({source_label}), "
            f"UV states = {len(E_uv)}, ECD states = {len(E_ecd)}"
        )

    names = sorted(conf_energies.keys())
    energies = np.array([conf_energies[n] for n in names], dtype=float)

    E_min = np.min(energies)
    delta_E = energies - E_min
    beta = 1.0 / (KB_HARTREE_PER_K * args.temperature)
    boltz_factors = np.exp(-beta * delta_E)
    weights = boltz_factors / np.sum(boltz_factors)

    print("\n[INFO] 玻尔兹曼权重：")
    for n, E, dE, w in zip(names, energies, delta_E, weights):
        dE_kJmol = dE * HARTREE_TO_KJMOL
        print(
            f"       {n:10s}: E = {E: .8f} Eh, "
            f"ΔE = {dE_kJmol: .3f} kJ/mol, "
            f"w = {w:.6f}, "
            f"source = {conf_energy_source[n]}"
        )

    weights_table_path = os.path.join(
        spectra_dir, f"{args.prefix}_boltzmann_weights.tsv"
    )
    with open(weights_table_path, "w", encoding="utf-8") as f:
        f.write("# conformer\tEnergy_Eh\tDeltaE_kJmol\tWeight\tEnergySource\n")
        for n, E, dE, w in zip(names, energies, delta_E, weights):
            dE_kJmol = dE * HARTREE_TO_KJMOL
            f.write(
                f"{n}\t{E:.10f}\t{dE_kJmol:.6f}\t{w:.10f}\t{conf_energy_source[n]}\n"
            )
    print(f"\n[INFO] 玻尔兹曼权重已写入: {weights_table_path}")

    E_grid = build_energy_grid(args.emin, args.emax, args.estep)
    lam_grid, order = energy_to_wavelength(E_grid)

    conf_uv_Egrid: Dict[str, np.ndarray] = {}
    conf_uv_lambda: Dict[str, np.ndarray] = {}
    conf_ecd_Egrid: Dict[str, np.ndarray] = {}
    conf_ecd_lambda: Dict[str, np.ndarray] = {}

    for n in names:
        I_E_uv = gaussian_broadening(E_grid, uv_E[n], uv_I[n], args.fwhm)
        conf_uv_Egrid[n] = I_E_uv
        conf_uv_lambda[n] = I_E_uv[order]

        I_E_ecd = gaussian_broadening(E_grid, ecd_E[n], ecd_R[n], args.fwhm)
        conf_ecd_Egrid[n] = I_E_ecd
        conf_ecd_lambda[n] = I_E_ecd[order]

    total_uv_E = np.zeros_like(E_grid)
    total_ecd_E = np.zeros_like(E_grid)
    for n, w in zip(names, weights):
        total_uv_E += w * conf_uv_Egrid[n]
        total_ecd_E += w * conf_ecd_Egrid[n]

    total_uv_lambda = total_uv_E[order]
    total_ecd_lambda = total_ecd_E[order]

    # UV all confs + Boltzmann
    uv_matrix = np.zeros((lam_grid.shape[0], len(names) + 2), dtype=float)
    uv_matrix[:, 0] = lam_grid
    for i, n in enumerate(names):
        uv_matrix[:, 1 + i] = conf_uv_lambda[n]
    uv_matrix[:, 1 + len(names)] = total_uv_lambda

    uv_header_cols = ["lambda_nm"] + names + ["Boltzmann_averaged"]
    uv_all_nm_path = os.path.join(
        spectra_dir, f"{args.prefix}_UV_all_confs_nm.tsv"
    )
    np.savetxt(
        uv_all_nm_path,
        uv_matrix,
        header="\t".join(uv_header_cols),
        comments="",
    )
    print(f"[INFO] UV 所有构象 + Boltzmann (nm) 已写入: {uv_all_nm_path}")

    # ECD all confs + Boltzmann
    ecd_matrix = np.zeros((lam_grid.shape[0], len(names) + 2), dtype=float)
    ecd_matrix[:, 0] = lam_grid
    for i, n in enumerate(names):
        ecd_matrix[:, 1 + i] = conf_ecd_lambda[n]
    ecd_matrix[:, 1 + len(names)] = total_ecd_lambda

    ecd_header_cols = ["lambda_nm"] + names + ["Boltzmann_averaged"]
    ecd_all_nm_path = os.path.join(
        spectra_dir, f"{args.prefix}_ECD_all_confs_nm.tsv"
    )
    np.savetxt(
        ecd_all_nm_path,
        ecd_matrix,
        header="\t".join(ecd_header_cols),
        comments="",
    )
    print(f"[INFO] ECD 所有构象 + Boltzmann (nm) 已写入: {ecd_all_nm_path}")

    # UV/ECD total spectra
    uv_boltz_nm_path = os.path.join(
        spectra_dir, f"{args.prefix}_UV_boltzmann_nm.tsv"
    )
    np.savetxt(
        uv_boltz_nm_path,
        np.column_stack([lam_grid, total_uv_lambda]),
        header="lambda_nm\tIntensity_arb",
        comments="",
    )

    uv_boltz_eV_path = os.path.join(
        spectra_dir, f"{args.prefix}_UV_boltzmann_eV.tsv"
    )
    np.savetxt(
        uv_boltz_eV_path,
        np.column_stack([E_grid, total_uv_E]),
        header="Energy_eV\tIntensity_arb",
        comments="",
    )

    ecd_boltz_nm_path = os.path.join(
        spectra_dir, f"{args.prefix}_ECD_boltzmann_nm.tsv"
    )
    np.savetxt(
        ecd_boltz_nm_path,
        np.column_stack([lam_grid, total_ecd_lambda]),
        header="lambda_nm\tIntensity_arb",
        comments="",
    )

    ecd_boltz_eV_path = os.path.join(
        spectra_dir, f"{args.prefix}_ECD_boltzmann_eV.tsv"
    )
    np.savetxt(
        ecd_boltz_eV_path,
        np.column_stack([E_grid, total_ecd_E]),
        header="Energy_eV\tIntensity_arb",
        comments="",
    )

    print(
        f"[INFO] UV/ECD Boltzmann 总谱 TSV 已写入:\n"
        f"       {uv_boltz_nm_path}\n"
        f"       {uv_boltz_eV_path}\n"
        f"       {ecd_boltz_nm_path}\n"
        f"       {ecd_boltz_eV_path}"
    )

    # 画图：UV all
    fig, ax = plt.subplots(figsize=(7, 4))
    for n in names:
        ax.plot(lam_grid, conf_uv_lambda[n], lw=1.0, alpha=0.6, label=n)
    ax.plot(lam_grid, total_uv_lambda, lw=2.0, label="Boltzmann-averaged")
    ax.set_xlabel("Wavelength / nm")
    ax.set_ylabel("UV intensity (arb. units)")
    ax.set_title("UV: all conformers + Boltzmann average")
    ax.axhline(0.0, color="black", lw=0.8)
    ax.legend(frameon=False, fontsize=8)
    ax.set_xlim(lam_grid.min(), lam_grid.max())
    fig.tight_layout()
    uv_all_png = os.path.join(plots_dir, f"{args.prefix}_UV_all_confs_nm.png")
    fig.savefig(uv_all_png, dpi=300, bbox_inches="tight")
    plt.close(fig)

    # 画图：UV total
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.plot(lam_grid, total_uv_lambda, lw=2.0)
    ax.set_xlabel("Wavelength / nm")
    ax.set_ylabel("UV intensity (arb. units)")
    ax.set_title("UV: Boltzmann-averaged")
    ax.axhline(0.0, color="black", lw=0.8)
    ax.set_xlim(lam_grid.min(), lam_grid.max())
    fig.tight_layout()
    uv_boltz_png = os.path.join(plots_dir, f"{args.prefix}_UV_boltzmann_nm.png")
    fig.savefig(uv_boltz_png, dpi=300, bbox_inches="tight")
    plt.close(fig)

    # 画图：ECD all
    fig, ax = plt.subplots(figsize=(7, 4))
    for n in names:
        ax.plot(lam_grid, conf_ecd_lambda[n], lw=1.0, alpha=0.6, label=n)
    ax.plot(lam_grid, total_ecd_lambda, lw=2.0, label="Boltzmann-averaged")
    ax.set_xlabel("Wavelength / nm")
    ax.set_ylabel("ECD intensity (arb. units)")
    ax.set_title("ECD: all conformers + Boltzmann average")
    ax.axhline(0.0, color="black", lw=0.8)
    ax.legend(frameon=False, fontsize=8)
    ax.set_xlim(lam_grid.min(), lam_grid.max())
    fig.tight_layout()
    ecd_all_png = os.path.join(plots_dir, f"{args.prefix}_ECD_all_confs_nm.png")
    fig.savefig(ecd_all_png, dpi=300, bbox_inches="tight")
    plt.close(fig)

    # 画图：ECD total
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.plot(lam_grid, total_ecd_lambda, lw=2.0)
    ax.set_xlabel("Wavelength / nm")
    ax.set_ylabel("ECD intensity (arb. units)")
    ax.set_title("ECD: Boltzmann-averaged")
    ax.axhline(0.0, color="black", lw=0.8)
    ax.set_xlim(lam_grid.min(), lam_grid.max())
    fig.tight_layout()
    ecd_boltz_png = os.path.join(plots_dir, f"{args.prefix}_ECD_boltzmann_nm.png")
    fig.savefig(ecd_boltz_png, dpi=300, bbox_inches="tight")
    plt.close(fig)

    print(
        f"[INFO] 图已写入:\n"
        f"       {uv_all_png}\n"
        f"       {uv_boltz_png}\n"
        f"       {ecd_all_png}\n"
        f"       {ecd_boltz_png}"
    )

    print("[INFO] post-processing finished")


if __name__ == "__main__":
    main()
EOF
chmod +x "${POSTPROCESS_PY}"

###################### WRITE R: ecd_plot.R ################################

cat > "${ECD_PLOT_R}" <<'EOF'
#!/usr/bin/env Rscript

## ECD + 可选 UV overlay
## 逻辑：
## - 左轴范围：优先由实验 ECD 的最大/最小值决定
## - 右轴范围：优先由实验 UV 的最大/最小值决定
## - 计算 ECD/UV 仅按比例缩放到实验坐标系中显示，不参与决定坐标范围
## - UV 若有实验数据，则假定实验 UV 原始单位为 AU，统一乘以 1000 以 mAU 显示
## - 如果没有实验曲线，则回退到计算曲线决定对应轴范围
## - X 轴默认 200–450 nm，但可用 --xmin / --xmax 控制最终绘图范围

args <- commandArgs(trailingOnly = TRUE)

.is_num_token <- function(x) {
  grepl("^[-+]?\\d*(?:\\.\\d+)?(?:[eE][-+]?\\d+)?$", x)
}

get_arg <- function(name, default = NULL) {
  ks <- c(paste0("--", name), paste0("-", name))
  i  <- which(args %in% ks)
  if (!length(i)) return(default)
  if (i == length(args)) return(TRUE)
  v <- args[i + 1]
  if (startsWith(v, "-") && !.is_num_token(v)) return(TRUE)
  v
}

get_chr <- function(name, default = NULL) {
  v <- get_arg(name, default)
  if (identical(v, TRUE)) return(as.character(TRUE))
  v
}

get_num <- function(name, default) {
  v  <- get_arg(name, default)
  vn <- suppressWarnings(as.numeric(v))
  if (is.na(vn)) as.numeric(default) else vn
}

get_bool <- function(name, default = FALSE) {
  v <- get_arg(name, if (default) "TRUE" else "FALSE")
  tolower(as.character(v)) %in% c("1","t","true","yes","y")
}

## ------------ CLI 参数 ------------

CALC_ECD  <- get_chr("calc-ecd", NA)
CALC_UV   <- get_chr("calc-uv",  NA)
EXP_ECD   <- get_chr("exp-ecd",  NA)
EXP_UV    <- get_chr("exp-uv",   NA)
OUTPUT    <- get_chr("output",   "ECD_overlay.png")

XSHIFT_ECD <- get_num("xshift-ecd", 0)
XSHIFT_UV  <- get_num("xshift-uv",  0)

FWHM_ECD_NM <- get_num("fwhm-ecd-nm", 0)
FWHM_UV_NM  <- get_num("fwhm-uv-nm",  0)

SMOOTH_EXP_ECD_NM <- get_num("smooth-exp-ecd-nm", 3)
SMOOTH_EXP_UV_NM  <- get_num("smooth-exp-uv-nm",  0)

PNG_W   <- get_num("png-width",  1400)
PNG_H   <- get_num("png-height", 1000)
PNG_RES <- get_num("png-res",    200)

SHOW_UV <- get_bool("show-uv", FALSE)

## 新增：最终绘图 x 轴范围
XMIN <- get_num("xmin", 200)
XMAX <- get_num("xmax", 450)

## 如果实验 UV 原始单位是 AU，而图上想显示 mAU，这里就乘 1000
UV_UNIT_FACTOR <- 1000

if (!is.finite(XMIN) || !is.finite(XMAX) || XMAX <= XMIN) {
  stop("Invalid x-range: require xmax > xmin, got xmin=", XMIN, ", xmax=", XMAX)
}

XLIM <- c(XMIN, XMAX)

if (is.na(CALC_ECD) || !file.exists(CALC_ECD)) {
  stop("calc ECD file not found: ", CALC_ECD)
}

HAS_UV <- SHOW_UV && !is.na(CALC_UV) && file.exists(CALC_UV)
if (SHOW_UV && !HAS_UV) {
  stop("show-uv=TRUE but calc-uv file not found: ", CALC_UV)
}

get_sample_name <- function(calc_path) {
  abs_path <- tryCatch(
    normalizePath(calc_path, winslash = "/", mustWork = FALSE),
    error = function(e) calc_path
  )
  dir1  <- dirname(abs_path)
  base1 <- basename(dir1)

  if (base1 %in% c("filter", "plots", "plot", "results")) {
    base1 <- basename(dirname(dir1))
  }

  base1 <- gsub("^SpaD([_-]?)(\\d+.*)$", "SPA D\\1\\2", base1)
  base1
}
SAMPLE_NAME <- get_sample_name(CALC_ECD)

## ------------ 工具函数 ------------

read_calc_two_col <- function(path) {
  df <- read.table(path, header = TRUE, check.names = FALSE,
                   stringsAsFactors = FALSE)
  if (ncol(df) < 2) stop("Calc file must have at least 2 columns: ", path)
  nms <- names(df)

  wl_idx <- grep("lambda|wave|nm", nms, ignore.case = TRUE)
  if (!length(wl_idx)) wl_idx <- 1L
  wl <- suppressWarnings(as.numeric(df[[wl_idx[1]]]))

  cand_idx <- setdiff(seq_along(nms), wl_idx[1])
  inten <- NULL
  for (j in cand_idx) {
    v <- suppressWarnings(as.numeric(df[[j]]))
    if (all(is.na(v))) next
    inten <- v
    break
  }
  if (is.null(inten)) stop("No numeric intensity column found in: ", path)

  ok <- is.finite(wl) & is.finite(inten)
  if (!any(ok)) stop("No finite data in: ", path)

  out <- data.frame(wl = wl[ok], y = inten[ok], stringsAsFactors = FALSE)
  out <- out[order(out$wl), , drop = FALSE]

  list(wl = out$wl, y = out$y)
}

read_exp_two_col <- function(path) {
  if (is.na(path) || !file.exists(path)) return(NULL)

  df <- tryCatch(
    read.csv(path, stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e) NULL
  )
  if (is.null(df) || ncol(df) < 2) return(NULL)

  nms <- names(df)

  wl_idx <- grep("wavelength|lambda|wave|nm", nms, ignore.case = TRUE)
  y_idx  <- grep("circulardichroism|ecd|cd|absorbance|uv", nms, ignore.case = TRUE)

  if (!length(wl_idx)) wl_idx <- 1L

  if (!length(y_idx)) {
    cand <- setdiff(seq_along(nms), wl_idx[1])
    if (!length(cand)) return(NULL)
    y_idx <- cand[1]
  } else {
    y_idx <- setdiff(y_idx, wl_idx[1])
    if (!length(y_idx)) {
      cand <- setdiff(seq_along(nms), wl_idx[1])
      if (!length(cand)) return(NULL)
      y_idx <- cand[1]
    } else {
      y_idx <- y_idx[1]
    }
  }

  wl <- suppressWarnings(as.numeric(df[[wl_idx[1]]]))
  y  <- suppressWarnings(as.numeric(df[[y_idx]]))

  ok <- is.finite(wl) & is.finite(y)
  if (!any(ok)) return(NULL)

  out <- data.frame(wl = wl[ok], y = y[ok], stringsAsFactors = FALSE)
  out <- out[order(out$wl), , drop = FALSE]

  list(wl = out$wl, y = out$y)
}

interp_on_grid <- function(obj, grid) {
  if (is.null(obj)) return(rep(NA_real_, length(grid)))
  approx(x = obj$wl, y = obj$y, xout = grid, rule = 2, ties = mean)$y
}

gaussian_smooth_nm <- function(y, wl, fwhm_nm) {
  if (is.null(y) || all(!is.finite(y))) return(y)
  if (is.null(fwhm_nm) || is.na(fwhm_nm) || fwhm_nm <= 0) return(y)

  wl <- as.numeric(wl)
  y  <- as.numeric(y)

  d <- diff(wl)
  step <- median(d[is.finite(d)])
  if (!is.finite(step) || step <= 0) return(y)

  sigma <- fwhm_nm / (2 * sqrt(2 * log(2)))
  half_width_nm <- 3 * sigma
  n_half <- max(1L, ceiling(half_width_nm / step))

  x_idx <- (-n_half):n_half
  x_nm  <- x_idx * step
  kern  <- exp(-0.5 * (x_nm / sigma)^2)
  kern  <- kern / sum(kern)

  y0 <- y
  y0[!is.finite(y0)] <- 0
  ys <- as.numeric(stats::filter(y0, kern, sides = 2, circular = FALSE))
  nas <- is.na(ys)
  if (any(nas)) ys[nas] <- y0[nas]
  ys
}

range_with_padding <- function(v, pad_frac = 0.08, fallback = c(-1, 1)) {
  v <- v[is.finite(v)]
  if (!length(v)) return(fallback)

  r <- range(v)
  if (!all(is.finite(r))) return(fallback)

  if (diff(r) == 0) {
    pad <- max(abs(r[1]) * pad_frac, 1)
    return(c(r[1] - pad, r[2] + pad))
  }

  pad <- diff(r) * pad_frac
  c(r[1] - pad, r[2] + pad)
}

## ------------ 读计算曲线 ------------

calc_ecd <- read_calc_two_col(CALC_ECD)
calc_uv  <- if (HAS_UV) read_calc_two_col(CALC_UV) else NULL

wl_grid <- calc_ecd$wl
if (!all(is.finite(wl_grid))) stop("Non-finite wavelength in calc ECD file.")

if (!is.null(calc_uv)) {
  if (!isTRUE(all.equal(wl_grid, calc_uv$wl))) {
    yy <- approx(x = calc_uv$wl, y = calc_uv$y,
                 xout = wl_grid, rule = 2, ties = mean)$y
    calc_uv <- list(wl = wl_grid, y = yy)
  } else {
    yy <- calc_uv$y
    yy[!is.finite(yy)] <- 0
    calc_uv$y <- yy
  }
}

yy_ecd <- calc_ecd$y
yy_ecd[!is.finite(yy_ecd)] <- 0
calc_ecd$y <- yy_ecd

if (FWHM_ECD_NM > 0) {
  calc_ecd$y <- gaussian_smooth_nm(calc_ecd$y, wl_grid, FWHM_ECD_NM)
}
if (!is.null(calc_uv) && FWHM_UV_NM > 0) {
  calc_uv$y <- gaussian_smooth_nm(calc_uv$y, wl_grid, FWHM_UV_NM)
}

## ------------ 实验曲线 ------------

exp_ecd <- read_exp_two_col(EXP_ECD)
exp_uv  <- if (HAS_UV) read_exp_two_col(EXP_UV) else NULL

HAS_EXP_ECD <- !is.null(exp_ecd)
HAS_EXP_UV  <- !is.null(exp_uv)

if (HAS_EXP_ECD) {
  cat(sprintf("[INFO] Experimental ECD loaded: %d points from %s\n",
              length(exp_ecd$wl), EXP_ECD))
} else {
  cat(sprintf("[WARN] Experimental ECD NOT loaded: %s\n", EXP_ECD))
}

if (HAS_UV) {
  if (HAS_EXP_UV) {
    cat(sprintf("[INFO] Experimental UV loaded: %d points from %s\n",
                length(exp_uv$wl), EXP_UV))
  } else {
    cat(sprintf("[WARN] Experimental UV NOT loaded: %s\n", EXP_UV))
  }
}

yexp_ecd <- if (HAS_EXP_ECD) interp_on_grid(exp_ecd, wl_grid) else NULL
yexp_uv  <- if (HAS_EXP_UV)  interp_on_grid(exp_uv,  wl_grid) else NULL

if (!is.null(yexp_ecd) && any(is.finite(yexp_ecd)) && SMOOTH_EXP_ECD_NM > 0) {
  yexp_ecd <- gaussian_smooth_nm(yexp_ecd, wl_grid, SMOOTH_EXP_ECD_NM)
}
if (!is.null(yexp_uv) && any(is.finite(yexp_uv)) && SMOOTH_EXP_UV_NM > 0) {
  yexp_uv <- gaussian_smooth_nm(yexp_uv, wl_grid, SMOOTH_EXP_UV_NM)
}

## ------------ 仅按实验定标，计算按比例配合 ------------

idx_xlim <- wl_grid >= XLIM[1] & wl_grid <= XLIM[2]

## ECD 左轴：实验决定范围；计算按实验峰高缩放
if (!is.null(yexp_ecd) && any(is.finite(yexp_ecd[idx_xlim]))) {
  exp_ecd_in  <- yexp_ecd[idx_xlim & is.finite(yexp_ecd)]
  calc_ecd_in <- calc_ecd$y[idx_xlim & is.finite(calc_ecd$y)]

  exp_ecd_absmax  <- max(abs(exp_ecd_in), na.rm = TRUE)
  calc_ecd_absmax <- max(abs(calc_ecd_in), na.rm = TRUE)

  if (!is.finite(exp_ecd_absmax) || exp_ecd_absmax == 0) exp_ecd_absmax <- 1
  if (!is.finite(calc_ecd_absmax) || calc_ecd_absmax == 0) calc_ecd_absmax <- 1

  scale_ecd <- exp_ecd_absmax / calc_ecd_absmax
  y_ecd_plot_calc <- calc_ecd$y * scale_ecd
  y_ecd_plot_exp  <- yexp_ecd

  y1lim <- range_with_padding(exp_ecd_in, pad_frac = 0.08, fallback = c(-12, 12))
} else {
  y_ecd_plot_calc <- calc_ecd$y
  y_ecd_plot_exp  <- yexp_ecd
  y1lim <- range_with_padding(
    y_ecd_plot_calc[idx_xlim & is.finite(y_ecd_plot_calc)],
    pad_frac = 0.08,
    fallback = c(-12, 12)
  )
}
y_ticks <- pretty(y1lim, n = 6)

if (!is.null(y_ecd_plot_exp) && any(is.finite(y_ecd_plot_exp))) {
  cat(sprintf("[INFO] Experimental ECD range used for left axis: %.6f to %.6f\n",
              min(y_ecd_plot_exp[idx_xlim], na.rm = TRUE),
              max(y_ecd_plot_exp[idx_xlim], na.rm = TRUE)))
}
cat(sprintf("[INFO] Calculated ECD range shown after scaling: %.6f to %.6f\n",
            min(y_ecd_plot_calc[idx_xlim], na.rm = TRUE),
            max(y_ecd_plot_calc[idx_xlim], na.rm = TRUE)))

## UV 右轴：实验决定范围；计算按实验峰高缩放；最终统一显示为 mAU
y2lim <- NULL
y_uv_plot <- NULL
yexp_uv_plot <- NULL
ylab_right <- NULL

if (HAS_UV && !is.null(calc_uv)) {
  if (!is.null(yexp_uv) && any(is.finite(yexp_uv[idx_xlim]))) {
    ## 实验 UV 原始 AU -> mAU
    exp_uv_in_raw  <- yexp_uv[idx_xlim & is.finite(yexp_uv)]
    exp_uv_in_mAU  <- exp_uv_in_raw * UV_UNIT_FACTOR
    yexp_uv_plot   <- yexp_uv * UV_UNIT_FACTOR

    calc_uv_in <- calc_uv$y[idx_xlim & is.finite(calc_uv$y)]

    exp_uv_absmax_mAU <- max(abs(exp_uv_in_mAU), na.rm = TRUE)
    calc_uv_absmax    <- max(abs(calc_uv_in), na.rm = TRUE)

    if (!is.finite(exp_uv_absmax_mAU) || exp_uv_absmax_mAU == 0) exp_uv_absmax_mAU <- 1
    if (!is.finite(calc_uv_absmax)    || calc_uv_absmax    == 0) calc_uv_absmax    <- 1

    scale_uv <- exp_uv_absmax_mAU / calc_uv_absmax
    y_uv_plot <- calc_uv$y * scale_uv

    y2lim <- range_with_padding(exp_uv_in_mAU, pad_frac = 0.08, fallback = c(0, 1000))
    ylab_right <- "UV absorbance (mAU)"
  } else {
    y_uv_plot <- calc_uv$y
    y2lim <- range_with_padding(
      y_uv_plot[idx_xlim & is.finite(y_uv_plot)],
      pad_frac = 0.08,
      fallback = c(0, 1)
    )
    ylab_right <- "UV absorbance (relative)"
  }
}

if (!is.null(yexp_uv_plot) && any(is.finite(yexp_uv_plot[idx_xlim]))) {
  cat(sprintf("[INFO] Experimental UV range used for right axis (mAU): %.6f to %.6f\n",
              min(yexp_uv_plot[idx_xlim], na.rm = TRUE),
              max(yexp_uv_plot[idx_xlim], na.rm = TRUE)))
}
if (!is.null(y_uv_plot)) {
  if (!is.null(yexp_uv_plot) && any(is.finite(yexp_uv_plot[idx_xlim]))) {
    cat(sprintf("[INFO] Calculated UV range shown after scaling (mAU): %.6f to %.6f\n",
                min(y_uv_plot[idx_xlim], na.rm = TRUE),
                max(y_uv_plot[idx_xlim], na.rm = TRUE)))
  } else {
    cat(sprintf("[INFO] Calculated UV range shown (relative): %.6f to %.6f\n",
                min(y_uv_plot[idx_xlim], na.rm = TRUE),
                max(y_uv_plot[idx_xlim], na.rm = TRUE)))
  }
}

## ------------ 画图 ------------

dir.create(dirname(OUTPUT), recursive = TRUE, showWarnings = FALSE)
png(OUTPUT, width = PNG_W, height = PNG_H, res = PNG_RES)

op <- par(no.readonly = TRUE)
on.exit(par(op), add = TRUE)

par(
  mgp = c(1.9, 0.6, 0),
  mar = c(4.2, 4.8, 3.0, if (HAS_UV) 4.8 else 3.0),
  tcl = -0.3,
  cex.axis = 1.05,
  cex.lab  = 1.15,
  xaxs = "i",
  yaxs = "i"
)

wl_ecd_plot <- wl_grid + XSHIFT_ECD

main_title <- if (HAS_UV) {
  sprintf("%s — ECD & UV spectra (calc vs exp)", SAMPLE_NAME)
} else {
  sprintf("%s — ECD spectra (calc vs exp)", SAMPLE_NAME)
}

plot(
  wl_ecd_plot, y_ecd_plot_calc,
  type = "l", lwd = 2.6, col = "red",
  xlab = "Wavelength (nm)",
  ylab = "ECD (mdeg)",
  ylim = y1lim,
  xlim = XLIM,
  main = main_title,
  yaxt = "n",
  frame.plot = FALSE
)
axis(2, at = y_ticks, lwd = 1.2)
box(lwd = 1.2)

if (!is.null(y_ecd_plot_exp) && any(is.finite(y_ecd_plot_exp))) {
  lines(wl_grid, y_ecd_plot_exp, col = "black", lwd = 2.0)
}

if (HAS_UV && !is.null(calc_uv) && !is.null(y2lim)) {
  wl_uv_plot <- wl_grid + XSHIFT_UV

  par(new = TRUE)
  plot(
    wl_uv_plot, y_uv_plot * 0,
    type = "n", axes = FALSE, xlab = "", ylab = "",
    ylim = y2lim, xlim = XLIM
  )
  axis(4, lwd = 1.2)
  mtext(ylab_right, side = 4, line = 3.0)

  lines(wl_uv_plot, y_uv_plot, col = "blue", lwd = 2.0)

  if (!is.null(yexp_uv_plot) && any(is.finite(yexp_uv_plot))) {
    lines(wl_grid, yexp_uv_plot, col = "black", lwd = 1.8, lty = 2)
  }
}

## ------------ 图例 ------------

leg_txt <- c("ECD (calc)")
leg_col <- c("red")
leg_lty <- c(1)
leg_lwd <- c(2.6)

if (!is.null(y_ecd_plot_exp) && any(is.finite(y_ecd_plot_exp))) {
  leg_txt <- c(leg_txt, "ECD (exp)")
  leg_col <- c(leg_col, "black")
  leg_lty <- c(leg_lty, 1)
  leg_lwd <- c(leg_lwd, 2.0)
}

if (HAS_UV && !is.null(calc_uv)) {
  leg_txt <- c(leg_txt, "UV (calc)")
  leg_col <- c(leg_col, "blue")
  leg_lty <- c(leg_lty, 1)
  leg_lwd <- c(leg_lwd, 2.0)
}

if (!is.null(yexp_uv_plot) && any(is.finite(yexp_uv_plot))) {
  leg_txt <- c(leg_txt, "UV (exp)")
  leg_col <- c(leg_col, "black")
  leg_lty <- c(leg_lty, 2)
  leg_lwd <- c(leg_lwd, 1.8)
}

legend("topright", bty = "n", inset = 0.02,
       legend = leg_txt, col = leg_col,
       lty = leg_lty, lwd = leg_lwd)

dev.off()

cat("[OK] Wrote plot to: ", OUTPUT, "\n")
EOF
chmod +x "${ECD_PLOT_R}"

###################### WRITE PYTHON: smart_filter_conformers.py ################################

SMART_FILTER="${SRC_DIR}/smart_filter_conformers.py"
cat > "${SMART_FILTER}" <<'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Smart conformer filtering:
1) 先用玻尔兹曼累计概率（--prob, 默认0.95）从低能到高能选出“候选集合”；
2) 在候选集合内按重原子 RMSD（Kabsch 对齐）做去冗余聚类；
3) 代表构象数控制在 [--floor, --cap]（默认 6–12）之间；
4) 输出 conf_###/conf.xyz、合并的 ensemble_filtered.xyz、选择明细 conformer_selection.csv、README.txt；
5) 默认打印统计信息（总帧数、候选数、最终RMSD阈值、代表最大ΔE等）。

注意：
- “聚类”只是选代表，不改变玻尔兹曼权重的总覆盖度；覆盖度由候选集合（按 --prob 取的能量窗口）决定。
- 若能量文件缺失则等权；floor 不足时会逐步放宽概率阈值再聚类，最后仍不足则按最低能回填。
"""

import os, sys, argparse
from pathlib import Path
from typing import List, Tuple, Optional
import numpy as np
import pandas as pd

KB_KCAL_PER_MOL_K = 0.00198720425864083

# ---------- IO ----------
def read_multiframe_xyz(xyz_path: Path) -> Tuple[List[str], List[np.ndarray]]:
    lines = xyz_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    frames = []
    symbols_ref = None
    i, n = 0, len(lines)
    while i < n:
        try:
            nat = int(lines[i].strip())
        except Exception:
            i += 1; continue
        if i + 2 + nat > n: break
        block = lines[i+2:i+2+nat]
        syms, crd = [], []
        ok = True
        for ln in block:
            parts = ln.split()
            if len(parts) < 4:
                ok = False; break
            syms.append(parts[0])
            try:
                crd.append([float(parts[1]), float(parts[2]), float(parts[3])])
            except Exception:
                ok = False; break
        if ok:
            if symbols_ref is None:
                symbols_ref = syms
            elif syms != symbols_ref:
                raise ValueError("Atom order differs across frames; cannot RMSD-align safely.")
            frames.append(np.array(crd, dtype=float))
        i += 2 + nat
    if not frames:
        raise ValueError(f"No frames in {xyz_path}")
    return symbols_ref, frames

def write_single_xyz(symbols: List[str], coords: np.ndarray, out_path: Path, comment: str = ""):
    nat = len(symbols)
    out = [str(nat), comment.strip()]
    for s, (x,y,z) in zip(symbols, coords):
        out.append(f"{s} {x:.6f} {y:.6f} {z:.6f}")
    out_path.write_text("\n".join(out)+"\n", encoding="utf-8")

def write_multiframe_xyz(symbols: List[str], coords_list: List[np.ndarray], out_path: Path, comments: Optional[List[str]]=None):
    buf = []
    for k, crd in enumerate(coords_list, 1):
        buf.append(str(len(symbols)))
        buf.append(comments[k-1] if comments and k-1 < len(comments) else f"frame {k}")
        for s, (x,y,z) in zip(symbols, crd):
            buf.append(f"{s} {x:.6f} {y:.6f} {z:.6f}")
    out_path.write_text("\n".join(buf)+"\n", encoding="utf-8")

def mkdir(p: Path):
    p.mkdir(parents=True, exist_ok=True)

# ---------- Energies & populations ----------
def read_crest_energies_table(path: Path) -> pd.DataFrame:
    """
    解析常见 crest.energies：
    典型列：idx  Erel[kcal/mol]  Eabs  weight
    提取 0-based idx、相对能量 rel_kcal、可选权重 weight。
    """
    if not path.exists(): return pd.DataFrame()
    rows = []
    for ln in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        l = ln.strip()
        if not l or l.startswith("#") or l.lower().startswith("idx"):
            continue
        parts = l.split()
        if len(parts) < 2:
            continue
        try:
            idx = int(parts[0]) - 1 if parts[0].isdigit() else None
            rel = float(parts[1])
            w = float(parts[3]) if len(parts) >= 4 else None
            rows.append({"idx": idx, "rel_kcal": rel, "weight": w})
        except Exception:
            continue
    return pd.DataFrame(rows)

def boltz_weights_from_rel_kcal(rel_kcal: np.ndarray, temp: float) -> np.ndarray:
    beta = 1.0 / (KB_KCAL_PER_MOL_K * temp)
    x = -beta * rel_kcal
    x -= np.max(x)  # 稳定数值
    w = np.exp(x)
    s = w.sum()
    return w / s if s > 0 else np.ones_like(w)/len(w)

def pick_by_cumprob(order_idx: List[int], probs: np.ndarray, prob_thr: float) -> List[int]:
    cs = np.cumsum(probs[order_idx])
    k = int(np.searchsorted(cs, prob_thr, side="left")) + 1
    k = min(max(1, k), len(order_idx))
    return order_idx[:k]

# ---------- RMSD (heavy atoms) ----------
PERIODIC = {
    "H":1, "He":2, "Li":3, "Be":4, "B":5, "C":6, "N":7, "O":8, "F":9, "Ne":10,
    "Na":11, "Mg":12, "Al":13, "Si":14, "P":15, "S":16, "Cl":17, "Ar":18, "K":19,
    "Ca":20, "Sc":21, "Ti":22, "V":23, "Cr":24, "Mn":25, "Fe":26, "Co":27, "Ni":28,
    "Cu":29, "Zn":30, "Ga":31, "Ge":32, "As":33, "Se":34, "Br":35, "Kr":36, "I":53, "Xe":54
}

def heavy_mask(symbols: List[str]) -> np.ndarray:
    return np.array([(PERIODIC.get(s, 0) > 1) for s in symbols], dtype=bool)

def kabsch_rmsd(P: np.ndarray, Q: np.ndarray) -> float:
    Pc = P - P.mean(axis=0, keepdims=True)
    Qc = Q - Q.mean(axis=0, keepdims=True)
    C = Pc.T @ Qc
    V, _, Wt = np.linalg.svd(C)
    d = np.sign(np.linalg.det(V @ Wt))
    D = np.diag([1.0, 1.0, d])
    U = V @ D @ Wt
    diff = Pc @ U - Qc
    return float(np.sqrt((diff*diff).sum()/P.shape[0]))

def greedy_cluster(frames: List[np.ndarray], order: List[int], thr: float) -> List[int]:
    reps = []
    for i in order:
        if not reps:
            reps.append(i); continue
        keep = True
        for r in reps:
            if kabsch_rmsd(frames[i], frames[r]) < thr:
                keep = False; break
        if keep:
            reps.append(i)
    return reps

# ---------- main ----------
def parse_args():
    ap = argparse.ArgumentParser(description="Smart conformer filter (Boltzmann coverage + heavy-atom RMSD).")
    ap.add_argument("--input", required=True, help="包含 ensemble.xyz (和 crest.energies) 的目录，或一个 xyz 文件本身")
    ap.add_argument("--output", required=True, help="输出目录")
    ap.add_argument("--xyz", default="", help="可选：显式指定 xyz 路径")
    ap.add_argument("--prob", type=float, default=0.95, help="玻尔兹曼累计覆盖阈值 [0–1]")
    ap.add_argument("--temp", type=float, default=298.15, help="温度 (K)")
    ap.add_argument("--cap", type=int, default=12, help="聚类后最大代表数")
    ap.add_argument("--floor", type=int, default=6, help="代表数下限（不足则放宽 prob 或回填低能）")
    ap.add_argument("--rmsd-start", type=float, default=0.20, help="RMSD 起始阈值 (Å)")
    ap.add_argument("--rmsd-step", type=float, default=0.05, help="RMSD 步长 (Å)")
    ap.add_argument("--rmsd-max", type=float, default=1.20, help="RMSD 最大阈值 (Å)")
    return ap.parse_args()

def main():
    a = parse_args()
    in_path = Path(a.input).expanduser().resolve()
    out_dir = Path(a.output).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    # xyz
    if a.xyz:
        xyz_path = Path(a.xyz).expanduser().resolve()
        base_dir = xyz_path.parent
    else:
        if in_path.is_file():
            xyz_path = in_path
            base_dir = xyz_path.parent
        else:
            xyz_path = in_path / "ensemble.xyz"
            base_dir = in_path
    if not xyz_path.exists():
        raise FileNotFoundError(f"ensemble.xyz not found: {xyz_path}")

    # energies
    ener_path = base_dir / "stage0_crest" / "crest.energies"
    if not ener_path.exists():
        ener_path = base_dir / "crest.energies"

    print(f"[i] xyz:   {xyz_path}")
    print(f"[i] ener:  {ener_path if ener_path.exists() else '(missing)'}")
    print(f"[i] out:   {out_dir}")

    symbols, frames = read_multiframe_xyz(xyz_path)
    mask = heavy_mask(symbols)
    frames_H = [f[mask] if mask.any() else f for f in frames]
    n = len(frames)

    # energies / populations
    df = read_crest_energies_table(ener_path) if ener_path.exists() else pd.DataFrame()
    if not df.empty and df["idx"].notna().all():
        m = min(n, df.shape[0])
        df = df.iloc[:m].copy()
        rel = df["rel_kcal"].to_numpy()
        w0 = df["weight"].to_numpy() if "weight" in df.columns and df["weight"].notna().any() else None
        order = list(np.argsort(rel))  # 低能→高能
        if w0 is not None and np.isfinite(w0).all() and (w0 > 0).any():
            probs = w0 / w0.sum()
        else:
            probs = boltz_weights_from_rel_kcal(rel - np.min(rel), a.temp)
        pick = pick_by_cumprob(order, probs, a.prob)
    else:
        order = list(range(n))
        probs = np.ones(n) / n
        pick = list(range(n))

    # 初次聚类（限制在 cap 以内）
    start_thr, step, thr_max = a.rmsd_start, a.rmsd_step, a.rmsd_max
    thr = start_thr
    pick_frames = [frames_H[i] for i in pick]
    rel_order = list(range(len(pick_frames)))  # 按能量序的相对索引
    while True:
        reps_rel = greedy_cluster(pick_frames, rel_order, thr)
        if len(reps_rel) <= a.cap or thr >= thr_max:
            break
        thr += step
    reps_abs = [pick[i] for i in reps_rel]

    # floor：保证至少 a.floor 个（必要时放宽 prob 再聚类）
    if len(reps_abs) < a.floor:
        prob_now = a.prob
        if ener_path.exists() and not df.empty:
            rel_arr = df["rel_kcal"].to_numpy()
            order_all = list(np.argsort(rel_arr))
            probs_all = boltz_weights_from_rel_kcal(rel_arr - np.min(rel_arr), a.temp)
        else:
            order_all = list(range(n))
            probs_all = np.ones(n)/n

        while len(reps_abs) < a.floor and prob_now < 0.999:
            prob_now = min(0.999, prob_now + 0.02)
            pick_more = pick_by_cumprob(order_all, probs_all, prob_now)
            cand = sorted(set(pick) | set(pick_more))
            cand_frames = [frames_H[i] for i in cand]
            rel_order = list(range(len(cand_frames)))
            thr_use = start_thr
            while True:
                reps_rel = greedy_cluster(cand_frames, rel_order, thr_use)
                reps_abs = [cand[i] for i in reps_rel]
                if len(reps_abs) >= a.floor or thr_use >= thr_max:
                    break
                thr_use += step
            thr = max(thr, thr_use)

        # 若仍不足：最低能回填
        unseen = [i for i in (order_all if 'order_all' in locals() else order) if i not in reps_abs]
        for i in unseen:
            reps_abs.append(i)
            if len(reps_abs) >= a.floor:
                break

    # cap 保证
    if len(reps_abs) > a.cap:
        if ener_path.exists() and not df.empty:
            rel_all = df["rel_kcal"].to_numpy()
            reps_abs = sorted(reps_abs, key=lambda i: rel_all[i])[:a.cap]
        else:
            reps_abs = sorted(reps_abs)[:a.cap]

    # 最终排序（能量优先）
    if ener_path.exists() and not df.empty:
        rel_all = df["rel_kcal"].to_numpy()
        reps_abs.sort(key=lambda i: rel_all[i])
        rel_used = rel_all
    else:
        reps_abs.sort()
        rel_used = None

    # ---------- 写输出 ----------
    kept_coords = [frames[i] for i in reps_abs]
    comments, rows = [], []
    for rank, idx0 in enumerate(reps_abs, 1):
        e = (rel_used[idx0] if rel_used is not None else None)
        cmt = f"rank={rank} src_idx={idx0+1}" + (f" Erel={e:.3f} kcal/mol" if e is not None else "")
        comments.append(cmt)
        d = out_dir / f"conf_{rank:03d}"
        d.mkdir(parents=True, exist_ok=True)
        write_single_xyz(symbols, frames[idx0], d/"conf.xyz", comment=cmt)
        rows.append({
            "rank": rank,
            "source_index": idx0+1,
            "Erel_kcal": (f"{e:.6f}" if e is not None else ""),
            "rmsd_threshold_A": f"{thr:.3f}"
        })

    write_multiframe_xyz(symbols, kept_coords, out_dir/"ensemble_filtered.xyz", comments)
    pd.DataFrame(rows).to_csv(out_dir/"conformer_selection.csv", index=False)

    # ---------- 统计信息 ----------
    total_frames = len(frames)
    cum_prob_pick = float(np.sum(probs[pick])) if len(pick) else 0.0
    print(f"[stat] total_frames={total_frames}")
    print(f"[stat] picked_for_prob={len(pick)}  cum_prob≈{cum_prob_pick:.3f}")
    print(f"[stat] final_representatives={len(reps_abs)}  final_rmsd≈{thr:.2f} Å")
    if rel_used is not None and len(reps_abs):
        emax = max(rel_used[i] for i in reps_abs)
        emin = min(rel_used[i] for i in reps_abs)
        print(f"[stat] Erel(min,max of reps)≈({emin:.3f}, {emax:.3f}) kcal/mol")

    readme = [
        f"Input xyz: {xyz_path}",
        f"Energies: {ener_path if ener_path.exists() else '(missing)'}",
        f"Total frames: {len(frames)}",
        f"Boltzmann coverage target (pre-cluster): {a.prob}",
        f"Temperature: {a.temp} K",
        f"Final RMSD threshold: ~{thr:.2f} Å (heavy atoms)",
        f"Kept: {len(reps_abs)} (cap={a.cap}, floor={a.floor})"
    ]
    (out_dir/"README.txt").write_text("\n".join(readme)+"\n", encoding="utf-8")

    print(f"[ok] kept {len(reps_abs)} conformers → {out_dir}")
    print("     - conf_###/conf.xyz")
    print("     - ensemble_filtered.xyz")
    print("     - conformer_selection.csv")
    print("     - README.txt")

if __name__ == "__main__":
    main()
EOF
chmod +x "${SMART_FILTER}"

###################### WRITE PYTHON: gen_orca_inputs.py ################################

GEN_ORCA="${SRC_DIR}/gen_orca_inputs.py"
cat > "${GEN_ORCA}" <<'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
from pathlib import Path

def parse_args():
    p = argparse.ArgumentParser(description="Generate clean ORCA .inp files (no RI)")
    p.add_argument('--input', required=True, type=Path, help='Directory containing conf_### folders with conf.xyz')
    p.add_argument('--title', default='', help='Comment title placed at top; default: "<jobdir> conf_xxx <task>"')
    p.add_argument('--task', choices=['optfreq','ecd','sp'], default='optfreq', help='Which input to generate')
    p.add_argument('--method', default='r2SCAN-3c', help='Method for OPT/FREQ')
    p.add_argument('--basis', default='', help='Basis set for OPT/FREQ (ignored for r2SCAN-3c)')
    p.add_argument('--method-ecd', default='CAM-B3LYP', help='Method for ECD TD-DFT')
    p.add_argument('--basis-ecd', default='def2-TZVP', help='Basis for ECD TD-DFT')
    p.add_argument('--nroots', type=int, default=60, help='Number of excited states for TD-DFT')
    p.add_argument('--use-moinp', action='store_true', help='If opt_freq.gbw exists, reuse it via %moinp')
    p.add_argument('--method-sp', default='PWPB95', help='Method for SP')
    p.add_argument('--basis-sp', default='def2-QZVPP', help='Basis for SP')
    p.add_argument('--sp-use-moinp', action='store_true', help='If opt_freq.gbw exists, reuse it via %moinp for SP')
    p.add_argument('--geom-mode', choices=['embed','xyzfile'], default='embed')
    p.add_argument('--charge', type=int, default=0)
    p.add_argument('--multiplicity', type=int, default=1)
    p.add_argument('--nproc', '--nprocs', dest='nprocs', type=int, default=16)
    p.add_argument('--mem', type=int, default=64)
    p.add_argument('--solvent', default='Methanol')
    p.add_argument('--extra-flags', default='TightSCF', help='Extra flags appended to the ! line (Grid5/FinalGrid6 will be stripped)')
    return p.parse_args()

def read_xyz_block(xyz_path: Path) -> str:
    lines = xyz_path.read_text().strip().splitlines()
    if len(lines) < 3:
        raise ValueError(f"Invalid XYZ: {xyz_path}")
    n = int(lines[0].strip())
    coords = lines[2:2+n]
    if len(coords) < n:
        coords = [ln for ln in lines[2:] if ln.strip()][:n]
    return "\n".join(coords)

def per_core_maxcore_mb(total_gb: int, nprocs: int) -> int:
    return max(256, (max(1, total_gb)*1024)//max(1, nprocs))

def _sanitize_flags(tokens):
    drop = {"grid5", "finalgrid6"}
    out, seen = [], set()
    for t in (tokens or []):
        t = t.strip()
        if not t:
            continue
        if t.lower() in drop:
            continue
        if t not in seen:
            seen.add(t)
            out.append(t)
    return out

def _bang_line(parts, solvent: str) -> str:
    parts = list(parts)
    if solvent and "CPCM" not in [p.upper() for p in parts]:
        parts.append("CPCM")
    parts = _sanitize_flags(parts)
    return "! " + " ".join(parts)

def _augment_sp_parts_for_double_hybrid(parts, method_sp: str, basis_sp: str):
    """
    只对 single point 的双杂化方法补必要关键词：
      - def2/J
      - <basis>/C
      - RIJCOSX

    这是最小修补，不改你原有整体逻辑。
    """
    method_l = (method_sp or "").strip().lower()
    basis = (basis_sp or "").strip()

    # 常见双杂化 / RI-MP2相关方法判定
    double_hybrid_keywords = [
        "pwpb95", "ri-pwpb95",
        "dsd", "b2plyp", "mp2", "scs-mp2", "dlpno-mp2"
    ]

    is_double_hybrid_like = any(k in method_l for k in double_hybrid_keywords)
    if not is_double_hybrid_like:
        return parts

    upper_parts = [p.upper() for p in parts]

    # 补 def2/J
    if "DEF2/J" not in upper_parts:
        parts.append("def2/J")

    # 补 AuxC
    # 只在常见 def2 基组下自动补 <basis>/C
    if basis:
        auxc = f"{basis}/C"
        if auxc.upper() not in upper_parts:
            parts.append(auxc)

    # 补 RIJCOSX
    if "RIJCOSX" not in upper_parts:
        parts.append("RIJCOSX")

    return parts

def build_optfreq_inp(xyz: str, title: str, charge: int, mult: int,
                      method: str, basis: str, nprocs: int, mem_gb: int,
                      solvent: str, extra_flags: str) -> str:
    m, b = method.strip(), (basis or '').strip()
    parts = [m, "Opt", "Freq", "TightSCF"]
    if m.lower() != "r2scan-3c" and b:
        parts.insert(1, b)
    if extra_flags.strip():
        parts += extra_flags.split()
    bang = _bang_line(parts, solvent)

    lines = [
        f"# {title}",
        "%pal",
        f"  nprocs {nprocs}",
        "end",
        f"%maxcore {per_core_maxcore_mb(mem_gb, nprocs)}",
        "",
        bang,
    ]
    if solvent:
        lines += [
            "%cpcm",
            "  SMD true",
            f'  SMDsolvent "{solvent}"',
            "end",
            "",
        ]
    lines += [f"* xyz {charge} {mult}", xyz, "*", ""]
    return "\n".join(lines)

def build_ecd_inp(xyz: str, xyz_name: str, title: str, charge: int, mult: int,
                  method_ecd: str, basis_ecd: str, nroots: int,
                  nprocs: int, mem_gb: int, solvent: str,
                  extra_flags: str, use_moinp: bool, gbw_path: Path,
                  geom_mode: str) -> str:
    parts = [method_ecd, "TightSCF"]
    if basis_ecd:
        parts.insert(1, basis_ecd)
    if extra_flags.strip():
        parts += extra_flags.split()
    bang = _bang_line(parts, solvent)

    lines = [
        f"# {title}",
        "%pal",
        f"  nprocs {nprocs}",
        "end",
        f"%maxcore {per_core_maxcore_mb(mem_gb, nprocs)}",
        "",
    ]
    if use_moinp and gbw_path.exists():
        lines += [f'%moinp "{gbw_path.name}"', ""]

    lines.append(bang)

    if solvent:
        lines += [
            "%cpcm",
            "  SMD true",
            f'  SMDsolvent "{solvent}"',
            "end",
            "",
        ]

    lines += [
        "%tddft",
        f"  nroots {nroots}",
        "end",
        "",
    ]

    if geom_mode == "xyzfile":
        lines += [f"* xyzfile {charge} {mult} {xyz_name}", "*", ""]
    else:
        lines += [f"* xyz {charge} {mult}", xyz, "*", ""]
    return "\n".join(lines)

def build_sp_inp(xyz: str, xyz_name: str, title: str, charge: int, mult: int,
                 method_sp: str, basis_sp: str,
                 nprocs: int, mem_gb: int, solvent: str,
                 extra_flags: str, use_moinp: bool, gbw_path: Path,
                 geom_mode: str) -> str:
    parts = [method_sp, "TightSCF"]
    if basis_sp:
        parts.insert(1, basis_sp)
    if extra_flags.strip():
        parts += extra_flags.split()

    # 仅修 single point 的关键问题：双杂化方法自动补 RI/AuxC 相关关键词
    parts = _augment_sp_parts_for_double_hybrid(parts, method_sp, basis_sp)

    bang = _bang_line(parts, solvent)

    lines = [
        f"# {title}",
        "%pal",
        f"  nprocs {nprocs}",
        "end",
        f"%maxcore {per_core_maxcore_mb(mem_gb, nprocs)}",
        "",
    ]
    if use_moinp and gbw_path.exists():
        lines += [f'%moinp "{gbw_path.name}"', ""]

    lines.append(bang)

    if solvent:
        lines += [
            "%cpcm",
            "  SMD true",
            f'  SMDsolvent "{solvent}"',
            "end",
            "",
        ]

    if geom_mode == "xyzfile":
        lines += [f"* xyzfile {charge} {mult} {xyz_name}", "*", ""]
    else:
        lines += [f"* xyz {charge} {mult}", xyz, "*", ""]
    return "\n".join(lines)

def main():
    args = parse_args()
    root = args.input
    jobname = root.name
    for conf_dir in sorted(root.glob("conf_*")):
        if not conf_dir.is_dir():
            continue
        conf_xyz = conf_dir / "conf.xyz"
        if not conf_xyz.exists():
            print(f"[SKIP] Missing conf.xyz in {conf_dir.name}")
            continue
        try:
            title_base = args.title.strip() or f"{jobname} {conf_dir.name}"
            if args.task == "optfreq":
                xyz = read_xyz_block(conf_xyz)
                text = build_optfreq_inp(
                    xyz, f"{title_base} opt+freq",
                    args.charge, args.multiplicity,
                    args.method, args.basis,
                    args.nprocs, args.mem,
                    args.solvent, args.extra_flags,
                )
                out = conf_dir / "opt_freq.inp"
                out.write_text(text)
                print(f"[OK] {out.name} written in {conf_dir.name}")

            elif args.task == "ecd":
                opt_xyz = conf_dir / "opt_freq.xyz"
                if not opt_xyz.exists():
                    raise FileNotFoundError(f"Missing opt_freq.xyz in {conf_dir}")
                xyz = read_xyz_block(opt_xyz)
                gbw = conf_dir / "opt_freq.gbw"
                text = build_ecd_inp(
                    xyz, opt_xyz.name,
                    f"{title_base} ECD",
                    args.charge, args.multiplicity,
                    args.method_ecd, args.basis_ecd,
                    args.nroots, args.nprocs, args.mem,
                    args.solvent, args.extra_flags,
                    args.use_moinp, gbw, args.geom_mode,
                )
                out = conf_dir / "ecd.inp"
                out.write_text(text)
                print(f"[OK] {out.name} written in {conf_dir.name}")

            elif args.task == "sp":
                opt_xyz = conf_dir / "opt_freq.xyz"
                if not opt_xyz.exists():
                    raise FileNotFoundError(f"Missing opt_freq.xyz in {conf_dir}")
                xyz = read_xyz_block(opt_xyz)
                gbw = conf_dir / "opt_freq.gbw"
                text = build_sp_inp(
                    xyz, opt_xyz.name,
                    f"{title_base} SP",
                    args.charge, args.multiplicity,
                    args.method_sp, args.basis_sp,
                    args.nprocs, args.mem,
                    args.solvent, args.extra_flags,
                    args.sp_use_moinp, gbw, args.geom_mode,
                )
                out = conf_dir / "single_point.inp"
                out.write_text(text)
                print(f"[OK] {out.name} written in {conf_dir.name}")

        except Exception as e:
            print(f"[ERROR] Failed in {conf_dir.name}: {e}")

if __name__ == "__main__":
    main()
EOF
chmod +x "${GEN_ORCA}"

###################### CONDA ENV ################################

CONDA_BASE="$(dirname "$(dirname "$(which conda)")")"
source "${CONDA_BASE}/etc/profile.d/conda.sh"
conda activate rdkit

python - <<'PY'
import rdkit, numpy, pandas, matplotlib
print("[INFO] python deps ok")
PY

command -v crest >/dev/null 2>&1 || { echo "[ERROR] crest not found in PATH" >&2; exit 1; }

###################### MATCH INPUT FILES ################################

shopt -s nullglob
matched_files=( "${INPUT_DIR}/${PROJECT_NAME}"-*.mol2 )
if [[ ${#matched_files[@]} -eq 0 && -f "${INPUT_DIR}/${PROJECT_NAME}.mol2" ]]; then
  matched_files=( "${INPUT_DIR}/${PROJECT_NAME}.mol2" )
fi
if [[ ${#matched_files[@]} -eq 0 ]]; then
  echo "[ERROR] no input files found for project name $PROJECT_NAME in $INPUT_DIR" >&2
  exit 1
fi

printf '[INFO] matched files:\n'
printf '  %s\n' "${matched_files[@]}"

###################### ORCA RUNNER FUNCTIONS ################################

run_one_orca() {
  local conf_dir="$1"
  echo "[RUN] $conf_dir"
  (
    cd "$conf_dir" || exit 1
    "$ORCA_CMD" opt_freq.inp > opt_freq.log 2>&1
  )
}

run_one_orca_sp() {
  local conf_dir="$1"
  echo "[RUN-SP] $conf_dir"
  (
    cd "$conf_dir" || exit 1
    "$ORCA_CMD" single_point.inp > single_point.log 2>&1
  )
}

run_one_orca_ecd() {
  local conf_dir="$1"
  echo "[RUN-ECD] $conf_dir"
  (
    cd "$conf_dir" || exit 1
    "$ORCA_CMD" ecd.inp > ecd.log 2>&1
  )
}

export -f run_one_orca
export -f run_one_orca_sp
export -f run_one_orca_ecd
export ORCA_CMD

###################### MAIN PIPELINE LOOP ################################

for input_file in "${matched_files[@]}"; do
  BASE="$(basename "$input_file" .mol2)"
  BASE_DIR="${INPUT_DIR}/${BASE}"
  LOG_FILE="${INPUT_DIR}/${BASE}.log"
  FILTER_DIR="${BASE_DIR}/filter"

  echo "=================================================="
  echo "[INFO] Running pipeline for $BASE"
  echo "=================================================="

  ###################### CREST ################################

  bash "${SCRIPT_DIR}/run_crest.sh" \
    --input "${input_file}" \
    --name "${BASE_DIR}" \
    --project-dir "${PROJECT_DIR}" \
    --solvent "${SOLVENT}" \
    --charge "${CHARGE}" \
    --mult "${MULT}" \
    --crest-mode "${CREST_MODE}" \
    --ewin-input "${EWIN_INPUT}" | tee "${LOG_FILE}"

  if ! grep -q "crest finished" "${LOG_FILE}"; then
    echo "[ERROR] $BASE: crest did not finish successfully. Skip this molecule."
    continue
  fi

  if [[ ! -d "${BASE_DIR}" ]]; then
    echo "[ERROR] $BASE: output directory not found: $BASE_DIR"
    continue
  fi

  conf_count=$(find "${BASE_DIR}" -maxdepth 1 -mindepth 1 -type d -name 'conf_*' | wc -l | awk '{print $1}')
  echo "[INFO] $BASE: conf_count=${conf_count}"

  ###################### SMART FILTER ################################

  if (( conf_count <= 20 )); then
    echo "[INFO] $BASE: <=20 conformers, use directly for downstream ORCA input."
    ORCA_INPUT_DIR="${BASE_DIR}"
  else
    echo "[INFO] $BASE: >20 conformers, running smart_filter_conformers.py"

    FILTER_LOG="${INPUT_DIR}/${BASE}_filter.log"
    TARGET_RMSD=0.75
    FILTER_CAP=12
    FILTER_FLOOR=6
    FILTER_PROB=0.95
    FILTER_TEMP=298.15
    RMSD_START=0.20
    RMSD_STEP=0.05
    RMSD_MAX=1.2
    MAX_CAP=384

    while true; do
      echo "[INFO] $BASE: running smart_filter_conformers.py with --cap $FILTER_CAP"
      rm -rf "${FILTER_DIR}"

      python3 "${SMART_FILTER}" \
        --input "${BASE_DIR}" \
        --output "${FILTER_DIR}" \
        --prob "${FILTER_PROB}" \
        --temp "${FILTER_TEMP}" \
        --cap "${FILTER_CAP}" \
        --floor "${FILTER_FLOOR}" \
        --rmsd-start "${RMSD_START}" \
        --rmsd-step "${RMSD_STEP}" \
        --rmsd-max "${RMSD_MAX}" | tee "${FILTER_LOG}"

      final_rmsd=$(grep 'final_rmsd' "${FILTER_LOG}" | tail -n 1 | grep -Eo '[0-9]+(\.[0-9]+)?' | tail -n 1 || true)
      if [[ -z "${final_rmsd}" ]]; then
        echo "[ERROR] $BASE: failed to parse final_rmsd from $FILTER_LOG"
        exit 1
      fi

      echo "[INFO] $BASE: parsed final_rmsd=${final_rmsd}"

      if awk "BEGIN {exit !(${final_rmsd} < ${TARGET_RMSD})}"; then
        echo "[INFO] $BASE: final_rmsd < $TARGET_RMSD, accept filtered conformers."
        break
      fi

      FILTER_CAP=$(( FILTER_CAP * 2 ))
      if (( FILTER_CAP > MAX_CAP )); then
        echo "[ERROR] $BASE: FILTER_CAP exceeded MAX_CAP=$MAX_CAP, stop."
        exit 1
      fi

      echo "[WARN] $BASE: final_rmsd=${final_rmsd} >= $TARGET_RMSD, retry with --cap $FILTER_CAP"
    done

    ORCA_INPUT_DIR="${FILTER_DIR}"
  fi

  echo "${ORCA_INPUT_DIR}" > "${BASE_DIR}/orca_input_dir.txt"
  echo "[INFO] $BASE: ORCA input directory = $ORCA_INPUT_DIR"

  if [[ ! -d "${ORCA_INPUT_DIR}" ]]; then
    echo "[ERROR] $BASE: ORCA input directory not found: $ORCA_INPUT_DIR"
    continue
  fi

  ###################### GENERATE ORCA OPTFREQ INPUTS ################################

  echo "[INFO] $BASE: generating ORCA optfreq inputs"
  python3 "${GEN_ORCA}" \
    --input "${ORCA_INPUT_DIR}" \
    --task optfreq \
    --method r2SCAN-3c \
    --charge "${CHARGE}" \
    --multiplicity "${MULT}" \
    --solvent "${SOLVENT}" \
    --nproc 16 \
    --mem 32 \
    --extra-flags ""

  ###################### RUN ORCA OPTFREQ ################################

  echo "[INFO] $BASE: running ORCA opt_freq in $ORCA_INPUT_DIR"
  cd "${ORCA_INPUT_DIR}" || exit 1

  running_jobs=0
  for d in conf_*; do
    [[ -d "$d" ]] || continue
    [[ -f "$d/opt_freq.inp" ]] || { echo "[SKIP] $BASE/$d missing opt_freq.inp"; continue; }

    bash -c 'run_one_orca "$1"' _ "$PWD/$d" &
    ((running_jobs+=1))

    if (( running_jobs >= MAX_JOBS )); then
      wait -n
      ((running_jobs-=1))
    fi
  done
  wait
  echo "[INFO] $BASE: all ORCA opt_freq jobs finished"

  ###################### CHECK OPTFREQ LOGS ################################

  grep -Hn -E "OPTIMIZATION HAS CONVERGED|Optimization converged|THE OPTIMIZATION HAS CONVERGED" conf_*/opt_freq.log || true
  grep -Hn -i "SCF CONVERGED" conf_*/opt_freq.log || true
  grep -Hn -i "imaginary" conf_*/opt_freq.log || true
  grep -Hn -E "(-[0-9]+\.[0-9]+\s*cm-1)|(-[0-9]+\s*cm-1)" conf_*/opt_freq.log || true

  for d in conf_*; do
    [[ -d "$d" ]] || continue
    [[ -s "$d/opt_freq.xyz" && -s "$d/opt_freq.gbw" ]] || echo "[MISS] $BASE/$d missing optimized outputs"
  done

  grep -Hn -iE "CPCM|SMD" conf_*/opt_freq.log | grep -iE "fail|error|singular|not converged" || true

  ###################### CLEAN FAILED OPTFREQ OUTPUTS ################################

  for d in conf_*; do
    [[ -d "$d" ]] || continue
    log="$d/opt_freq.log"
    [[ -f "$log" ]] || continue

    imag_count=$(awk '
      /Total number of imaginary perturbations/ {
        for (i=NF; i>=1; i--) {
          if ($i ~ /^[0-9]+$/) {
            print $i
            exit
          }
        }
      }' "$log")

    has_negative_freq=0
    if grep -Eq "^[[:space:]]*-[0-9]+(\.[0-9]+)?[[:space:]]*cm-1|[[:space:]]-[0-9]+(\.[0-9]+)?[[:space:]]*cm-1" "$log"; then
      has_negative_freq=1
    fi

    if { [[ -n "${imag_count}" ]] && (( imag_count > 0 )); } || (( has_negative_freq == 1 )); then
      echo "[CLEAN] $BASE/$d (imaginary frequency detected)"
      rm -f \
        "$d/opt_freq.log" \
        "$d/opt_freq.out" \
        "$d/opt_freq.xyz" \
        "$d/opt_freq.gbw" \
        "$d/opt_freq.densities" \
        "$d/opt_freq.property.txt" \
        "$d/opt_freq.engrad" \
        "$d/opt_freq.hess" \
        "$d/opt_freq.trj" \
        "$d/opt_freq.opt" \
        "$d/opt_freq.scfp" \
        "$d/opt_freq.tmp" \
        "$d/opt_freq.ges" \
        "$d/opt_freq.prop" \
        "$d/opt_freq.bas"* \
        "$d/opt_freq."*.tmp
      echo "[CLEAN] removed opt outputs in $BASE/$d, kept directory and conf.xyz"
    fi
  done

  ###################### WRITE G TABLE ################################

  {
    echo -e "conf\tE_Ha\tH_Ha\tTS_Ha\tG_Ha\tG_source"
    for f in conf_*/opt_freq.log conf_*/opt_freq.out; do
      [ -f "$f" ] || continue
      awk '
        /FINAL SINGLE POINT ENERGY/ {E=$NF; gotE=1}
        /TOTAL SCF ENERGY/          {Scf=$NF; gotScf=1}
        /[Gg]ibbs[^:]*[Ff]ree[^:]*[Ee]nergy/ {
          for(i=NF;i>=1;i--) if($i ~ /^-?[0-9]+(\.[0-9]+)?$/){G=$i; gotG=1; break}
        }
        /Total enthalpy/ {
          for(i=NF;i>=1;i--) if($i ~ /^-?[0-9]+(\.[0-9]+)?$/){H=$i; gotH=1; break}
        }
        /Total entropy correction/ {
          for(i=NF;i>=1;i--) if($i ~ /^-?[0-9]+(\.[0-9]+)?$/){TS=$i; gotTS=1; break}
        }
        END{
          fn=FILENAME
          sub(/\/opt_freq\.(log|out)$/,"",fn)
          e = (gotE?E:(gotScf?Scf:""))
          gsrc="NA"; g=""
          if(gotG){ g=G; gsrc="direct" }
          else if(gotH && gotTS){ g=H-TS; gsrc="HminusTS" }
          printf "%s\t%s\t%s\t%s\t%s\t%s\n", fn, e, (gotH?H:""), (gotTS?TS:""), (g==""?"":g), gsrc
        }' "$f"
    done | sort -k5,5g
  } > G_table.tsv


  echo "[INFO] $BASE: written ${ORCA_INPUT_DIR}/G_table.tsv"

  ###################### GENERATE ORCA SINGLE-POINT INPUTS ################################

  echo "[INFO] $BASE: generating ORCA single-point inputs"
  python3 "${GEN_ORCA}"     --input "${ORCA_INPUT_DIR}"     --task sp     --method-sp PWPB95     --basis-sp def2-QZVPP     --charge "${CHARGE}"     --multiplicity "${MULT}"     --solvent "${SOLVENT}"     --nproc 16     --mem 32     --extra-flags ""

  ###################### RUN ORCA SINGLE-POINT ################################

  echo "[INFO] $BASE: running ORCA single-point jobs in $ORCA_INPUT_DIR"
  cd "${ORCA_INPUT_DIR}" || exit 1

  running_jobs=0
  SP_MAX_JOBS=3

  for d in conf_*; do
    [[ -d "$d" ]] || continue
    [[ -f "$d/single_point.inp" ]] || { echo "[SKIP] $BASE/$d missing single_point.inp"; continue; }
    [[ -s "$d/opt_freq.xyz" ]] || { echo "[SKIP] $BASE/$d missing opt_freq.xyz"; continue; }

    bash -c 'run_one_orca_sp "$1"' _ "$PWD/$d" &
    ((running_jobs+=1))

    if (( running_jobs >= SP_MAX_JOBS )); then
      wait -n
      ((running_jobs-=1))
    fi
  done
  wait
  echo "[INFO] $BASE: all ORCA single-point jobs finished"

  ###################### CHECK SINGLE-POINT LOGS ################################

  grep -Hn -i "FINAL SINGLE POINT ENERGY" conf_*/single_point.log || true
  grep -Hn -i "SCF CONVERGED" conf_*/single_point.log || true

  for d in conf_*; do
    [[ -d "$d" ]] || continue
    [[ -f "$d/single_point.inp" ]] || continue
    [[ -s "$d/single_point.log" ]] || echo "[MISS] $BASE/$d missing single_point.log"
  done

  ###################### GENERATE ORCA ECD INPUTS ################################

  echo "[INFO] $BASE: generating ORCA ECD inputs"
  python3 "${GEN_ORCA}"     --input "${ORCA_INPUT_DIR}"     --task ecd     --method-ecd CAM-B3LYP     --basis-ecd def2-TZVP     --nroots 60     --charge "${CHARGE}"     --multiplicity "${MULT}"     --solvent "${SOLVENT}"     --nproc 1     --mem 32

  ###################### RUN ORCA ECD ################################

  echo "[INFO] $BASE: running ORCA ECD jobs in $ORCA_INPUT_DIR"
  cd "${ORCA_INPUT_DIR}" || exit 1

  running_jobs=0
  ECD_MAX_JOBS=3

  for d in conf_*; do
    [[ -d "$d" ]] || continue
    [[ -f "$d/ecd.inp" ]] || { echo "[SKIP] $BASE/$d missing ecd.inp"; continue; }
    [[ -s "$d/opt_freq.xyz" ]] || { echo "[SKIP] $BASE/$d missing opt_freq.xyz"; continue; }

    bash -c 'run_one_orca_ecd "$1"' _ "$PWD/$d" &
    ((running_jobs+=1))

    if (( running_jobs >= ECD_MAX_JOBS )); then
      wait -n
      ((running_jobs-=1))
    fi
  done
  wait
  echo "[INFO] $BASE: all ORCA ECD jobs finished"

  ###################### CHECK ECD LOGS ################################

  grep -Hn -i "TD-DFT" conf_*/ecd.log || true
  grep -Hn -i "ABSORPTION SPECTRUM VIA TRANSITION ELECTRIC DIPOLE MOMENTS" conf_*/ecd.log || true
  grep -Hn -i "CD SPECTRUM" conf_*/ecd.log || true
  grep -Hn -i "SCF CONVERGED" conf_*/ecd.log || true

  for d in conf_*; do
    [[ -d "$d" ]] || continue
    [[ -f "$d/ecd.inp" ]] || continue
    [[ -s "$d/ecd.log" ]] || echo "[MISS] $BASE/$d missing ecd.log"
  done

done

###################### PIPELINE FINISHED ################################

echo "[INFO] pipeline finished"

  ###################### ORCA POSTPROCESS ################################

  echo "[INFO] $BASE: running ORCA ECD postprocess"
  POSTPROCESS_LOG="${INPUT_DIR}/${BASE}_postprocess.log"

  python3 "${POSTPROCESS_PY}"     --root "${ORCA_INPUT_DIR}"     --prefix "${BASE}"     --energy-source single_point     --temperature 298.15     --fwhm 0.30     --emin 2.48     --emax 6.90     --estep 0.01 | tee "${POSTPROCESS_LOG}"

  if [[ ! -f "${ORCA_INPUT_DIR}/${BASE}_ECD_boltzmann_nm.tsv" ]]; then
    echo "[ERROR] $BASE: missing ${ORCA_INPUT_DIR}/${BASE}_ECD_boltzmann_nm.tsv after postprocess"
    continue
  fi
  if [[ ! -f "${ORCA_INPUT_DIR}/${BASE}_UV_boltzmann_nm.tsv" ]]; then
    echo "[ERROR] $BASE: missing ${ORCA_INPUT_DIR}/${BASE}_UV_boltzmann_nm.tsv after postprocess"
    continue
  fi

  ###################### FINAL ECD/UV PLOT ################################

  EXP_ECD_FILE="${INPUT_DIR}/${BASE}-ecd.csv"
  EXP_UV_FILE="${INPUT_DIR}/${BASE}-uv.csv"
  PLOT_LOG="${INPUT_DIR}/${BASE}_plot.log"

  if [[ -f "${EXP_ECD_FILE}" ]]; then
    if [[ -f "${EXP_UV_FILE}" ]]; then
      FINAL_PLOT="${ORCA_INPUT_DIR}/${BASE}_ECD_UV_overlay_200_450.png"
      echo "[INFO] $BASE: plotting ECD+UV overlay"
      Rscript "${ECD_PLOT_R}"         --calc-ecd "${ORCA_INPUT_DIR}/${BASE}_ECD_boltzmann_nm.tsv"         --calc-uv "${ORCA_INPUT_DIR}/${BASE}_UV_boltzmann_nm.tsv"         --exp-ecd "${EXP_ECD_FILE}"         --exp-uv "${EXP_UV_FILE}"         --output "${FINAL_PLOT}"         --xshift-ecd 0         --xshift-uv 0         --fwhm-ecd-nm 5         --fwhm-uv-nm 5         --xmin 200         --xmax 450         --show-uv TRUE | tee "${PLOT_LOG}"
    else
      FINAL_PLOT="${ORCA_INPUT_DIR}/${BASE}_ECD_overlay_200_450.png"
      echo "[WARN] $BASE: ${EXP_UV_FILE} not found, plotting ECD only"
      Rscript "${ECD_PLOT_R}"         --calc-ecd "${ORCA_INPUT_DIR}/${BASE}_ECD_boltzmann_nm.tsv"         --exp-ecd "${EXP_ECD_FILE}"         --output "${FINAL_PLOT}"         --xshift-ecd 0         --fwhm-ecd-nm 5         --xmin 200         --xmax 450         --show-uv FALSE | tee "${PLOT_LOG}"
    fi

    if [[ -f "${FINAL_PLOT}" ]]; then
      echo "[INFO] $BASE: final plot -> ${FINAL_PLOT}"
    else
      echo "[ERROR] $BASE: final plot not generated"
    fi
  else
    echo "[WARN] $BASE: ${EXP_ECD_FILE} not found, skip final overlay plot"
  fi


###################### PIPELINE FINISHED ################################

echo "[INFO] pipeline finished"