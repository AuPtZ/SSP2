---
output:
  word_document: default
  html_document: default
---
### Why we built SSP?
The burgeoning high-throughput technologies have led to a significant surge in the scale of **pharmacotranscriptomic datasets**, especially for oncology. **Signature search methods (SSMs)**, utilizing **oncogenic signature** formed by differentially expressed genes (DEGs) through sequencing, have been instrumental in anti-cancer drug screening and identifying mechanisms of action without relying on prior knowledge.  
However, various studies have found that different SSMs exhibit varying performance across pharmacotranscriptomic datasets. In addition, truncating the oncogenic signature to different sizes can also significantly impact the results of drug repurposing. Therefore, **finding the optimal SSMs and customized oncogenic signature for a specific disease remains a challenge**.  
**Signature Search Polestar (SSP)** is a webserver integrating the largest uniform drug profiles in L1000 with five state-of-the-art (XSum, CMap, GESA, ZhangScore, XCos) and provide three modules to facilitate drug repurposing:  
1.	Benchmark: Two metrics (AUC and Enrichment Score) based on drugs annotations are employed to evaluate the performance of SS methods at different top DEGs. The results indicate the best evaluation method and the top DEGs for input disease signature.  
2.	Robustness: A robust metric based on drug self-retrieval is developed to evaluate the overall performance of SS methods at different top DEGs. This module is applicable when meets insufficient drug annotations.  
3.	Application: Three tools (single method, SS_all, and SS_cross) enable user to utilize optimal SS methods with disease signatures. The results present scores of promising drug for oncogenic signature.  

Additionally, SSP webserver is deployed at a high performance servers for better user experience and we opensource all codes at [Gitee](https://gitee.com/auptz/benchmark-ss) or mirror repository [Github](https://gitee.com/auptz/benchmark-ss). Everyone could directly use or DIY own SSP webserver by interest.

<div style="padding: 10px; text-align: center;">
<img src="imginfo0.PNG" width = "80%" height = "80%" />
</div>


