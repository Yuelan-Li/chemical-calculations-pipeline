# ORCA ECD Workflow for Natural Products

A lightweight and reproducible workflow for conformer generation, filtering, ORCA input preparation, quantum chemical calculation, and ECD/UV post-processing.

Designed for small-molecule ECD calculations using ORCA, with support for batch processing.

---

## Version

v1.0.0 (stable, verified working)

---

## Features

- End-to-end ECD workflow (CREST → ORCA → spectrum)
- CREST-based conformer sampling (GFN2-xTB)
- Automated conformer filtering (energy + RMSD)
- ORCA input generation (OPT / FREQ / SP / TDDFT ECD)
- Boltzmann-weighted UV/ECD spectrum generation
- Experimental UV/ECD overlay visualization
- Batch-friendly shell workflow for HPC environments

---

## Workflow

1. Conformer search using CREST  
2. Conformer filtering to remove redundancy, if the number of conformers exceeds a user-defined threshold (default: >20)   
3. ORCA input generation  
4. ORCA calculations (SP + TDDFT ECD)  
5. Spectrum extraction and Boltzmann averaging  
6. UV/ECD plotting (optional)

---

## Requirements

- Linux (tested on Ubuntu 22.04.5 LTS)
- Bash ≥ 5.1
- Python ≥ 3.10
- CREST (tested: 3.0.2)
- ORCA (tested: 6.1.1)

ORCA must be installed and available in PATH.

---

## Repository Structure

.
├── run_ECD_gold.sh
├── scripts/
├── src/
├── data/
├── docs/
└── README.md

---

## Input

### Structure input (required)

Supported formats:

- .mol2    

Used for conformer search and quantum calculations.

---

### Experimental data (optional)

- UV spectrum: .csv  
- ECD spectrum: .csv  

Used only for plotting and comparison.

---

## Quick Start

nohup bash run_ECD_gold.sh \
  --legacy-input-dir path \
  --project-name test \
  > run_ECD_Date.log 2>&1 &

tail -f run_ECD.log

---

## Output

Typical outputs include:

- conf_XXX/ (conformers)
- *.inp (ORCA input)
- *.out (ORCA output)
- *_boltzmann_nm.tsv (spectra)
- *_overlay.png (plots)

---

## Important Notes

### Conformer sampling

- Too many → slow  
- Too few → inaccurate  

Recommended:

- initial: ~20 kcal/mol  


---

### UV wavelength shift

A wavelength shift (typically 10–30 nm) may be applied when comparing calculated and experimental UV spectra.

This depends on:

- functional  
- basis set  
- molecular system  

Do not treat this shift as a physical correction.

---

### ECD interpretation

Use:

- spectral shape  
- sign pattern  

Do NOT rely on absolute wavelength alignment.

---

## Typical Settings

### CREST
- GFN2-xTB  
- methanol  

### ORCA
- CAM-B3LYP / PWPB95  
- def2-TZVP / def2-QZVPP  
- CPCM (SMD)

---

## Applications

- Natural product stereochemistry  
- ECD prediction  
- Conformer-dependent analysis  
- Batch processing  

---

## Limitations

- No automatic error recovery  
- Depends on conformer quality  
- UV may require empirical shift  

---

## Design Philosophy

- reproducible  
- minimal manual intervention  
- modular  
- user friendly  

---

## License

MIT License

---

## Citation

If used, please cite:

- ORCA (Neese et al.)
- CREST (Grimme et al.)
