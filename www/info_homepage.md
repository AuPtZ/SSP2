**Signature Search Polestar (SSP)** is a webserver that integrates the largest uniform pharmacotranscriptomic datasets from LINCS L1000 with seven state-of-the-art Signature Search methods (SSMs). SSP allows users to evaluate these SSMs using cancere-drug similarity metrics and drug annotations, and suggests the optimal method and appropriate topN to construct a customized oncogenic signature. Additionally, SSP offers three effective approaches to query drugs for new repurposing based on specific oncogenic signature.    

**For new user, here is a brief introduction for you.**   
SSP is structured around **two primary modules** and **three auxiliary modules**. You can access the respective modules by clicking on the navigation bar buttons or the module buttons on the home page.    
   
<div style="padding: 10px; text-align: center;">
<img src="imginfohomepage1.png" width = "100%" height = "100%" />
</div>

Each module is accompanied by a detailed guide on the right panel.   
The primary modules, which are essential for drug repurposing, consist of the following:   
**Benchmark**: This module evaluates the performance of each SSM based on the user-provided oncogenic signature and drug annotations. It helps in determining the appropriate SSM and topN for further analysis.
**Application**: After identifying the appropriate SSM and topN through Benchmark, users can upload file and set parameters into the Application module for drug repurposing.      

The three auxiliary modules primarily support the aforementioned primary modules by offering functionalities such as data preprocessing and result retrieval:  
**Job Center**: A jobid is provided after successful submission in benchmark and application module. This module enable user to retrieves the results of computations. Demo result and interpretation are also provided.    
**Converter**: Facilitates the conversion of gene and drug identifiers into formats compatible with the Benchmark and Application.  
**Info**: Offers **help pages, demo files, scripts, supplementary document** and **organized pharmacotranscriptomic datasets** for users' convenience and ease of use.  

We strongly recommend that users first visit the **Benchmark module** or the **Info-Help page** to understand the  operational procedures and file requirements before preparing your work.  
For any inquiries, please click on the **"Contact us!"** link at the bottom of the website page for email consultation.

#### How to cite
If you use SSP2 in your research, please cite:

Zhang J, Yuan S, Cao W, Jiang X, Yang C, Jiang C, Liu R, Yang W, Tian S. **Signature Search Polestar: a comprehensive drug repurposing method evaluation assistant for customized oncogenic signature.** *Bioinformatics*. 2024;40(9):btae536. doi:10.1093/bioinformatics/btae536.
