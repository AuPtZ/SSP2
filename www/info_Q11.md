### Q&A collection from reviewers
#### 1. How the oncogenic signatures were determined ?
In SSP, oncogenic signatures is defined as a gene list with log2FC, which is derived from gene expression profile from tumor cell lines or cancer patient cohorts. 
We recommend utilizing sequencing data from patient cohorts, such as **ICGC/TCGA/GEO**, or from cell lines, and employing differential expression analysis to obtain the signature (with log2FC). 

#### 2. How the user should go about selecting a drug profile?
Since the CMAP database contains pharmacotranscriptomic data specific to tumor cell lines, we presume that users will select relevant drug datasets for cell lines based on the type of cancer they are studying. Furthermore, in previous studies of drug repurposing, many research subjects were not cancer-related, highlighting the significant potential of pharmacotranscriptomic data mining.      
However, there is ongoing debate regarding the most appropriate treat time and concentration to choose a large pharmacotranscriptomic dataset. To accommodate this diversity, we encourage users consider utilizing multiple datasets for calculations to obtain a more robust result. If a drug consistently ranks highly across different concentrations and treat time in the expression profiles, it is more likely to be effective. Based on our previous literature review, we generally recommend using pharmacotranscriptomic datasets at **6 hours with 10μM** or **24 hours with 10μM**.      


