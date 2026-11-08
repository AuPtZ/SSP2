**Signature Search Polestar 2 (SSP2)** is a webserver that integrates the largest uniform pharmacotranscriptomic datasets from LINCS L1000 with seven state-of-the-art Signature Search methods (SSMs). SSP2 lets users benchmark these SSMs against compound annotations, suggests the optimal method and topN for a customized query signature, and then queries either **compounds** or **CRISPR knockout target genes** (added in the current version as the `LINCS-CRISPR` data source, with an offline method/topN calibration panel).    

**For new user, here is a brief introduction for you.**   
SSP2 is structured around **two search modules** and several auxiliary modules. You can access the respective modules by clicking on the navigation bar buttons or the module buttons on the home page.    
   
<div style="padding: 10px; text-align: center;">
<img src="imginfohomepage1.png" width = "100%" height = "100%" alt="SSP2 homepage and module overview" />
</div>

Each module is accompanied by a detailed guide on the right panel.   
The two search modules consist of the following:   
**Benchmark**: This module evaluates the performance of each SSM on **compound datasets** based on the user-provided query signature and compound annotations. It helps in determining the appropriate SSM and topN for further analysis.
**Application**: After identifying the appropriate SSM and topN through Benchmark, users can upload a query signature and set parameters in the Application module. Besides compound datasets, the Application also supports **CRISPR knockout datasets** (`LINCS-CRISPR`): the ranked entities are then target genes, drug-detail popups are disabled, and an offline pilot calibration for that cell line is shown.

The auxiliary modules primarily support the search modules by offering functionalities such as data preprocessing and result retrieval:  
**Job Center**: A jobid is provided after successful submission in Benchmark and Application. This module lets users retrieve the results of computations; demo results and interpretation are also provided.    
**Converter**: Facilitates the conversion of gene and compound identifiers into formats compatible with the Benchmark and Application.  
**Info**: Offers **help pages, demo files, scripts, supplementary documentation** and **organized pharmacotranscriptomic datasets** for users' convenience and ease of use.  

We strongly recommend that users first visit the **Benchmark module** or the **Info-Help page** to understand the  operational procedures and file requirements before preparing your work.  
For any inquiries, please click on the **"Contact us!"** link at the bottom of the website page for email consultation.

#### How to cite
If you use SSP2 in your research, please cite:

Zhang J, Yuan S, Cao W, Jiang X, Yang C, Jiang C, Liu R, Yang W, Tian S. **Signature Search Polestar: a comprehensive drug repurposing method evaluation assistant for customized oncogenic signature.** *Bioinformatics*. 2024;40(9):btae536. doi:10.1093/bioinformatics/btae536.
