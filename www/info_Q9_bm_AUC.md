In result of AUC, the image is a scatter plot depicting the results of the **Area Under the Curve (AUC)** for different **signature search methods (SSMs)** across various TopN values. AUC is a metric used to evaluate the performance of SSMs, typically in drug efficacy classification tasks. There are five methods represented by different colored dots: **CMap (red)**, **GSEA (blue)**, **XCos (green)**, **XSum (purple)**, and **ZhangScore (orange)**. The AUC results for each method at different TopN values are plotted with the corresponding colored dots, with a smooth trend line for each method indicating the change in AUC as TopN increases.   
The vertical dashed line in the scatter plot indicates the position of the TopN value where the **maximum AUC** is achieved for one or more methods.  
<div style="padding: 10px; text-align: center;">
<img src="imginfoQ9_1.png" width = "80%" height = "80%" />
</div>

In the corresponding table below, the row with the TopN value associated with the **maximum** is placed at the forefront, and the cell containing the **maximum value** is highlighted in yellow.  
<div style="padding: 10px; text-align: center;">
<img src="imginfoQ9_2.png" width = "80%" height = "80%" />
</div>

**if you only upload a annotation for AUC, we recommend user select SSMs and topN with highest scores for later query in Application module. If the SSM in result exhibits monotonic increase, it is recommended to directly set the length of oncogenic signature to TopN for later query in Application module.**  
**if you upload both annotation for AUC and ES, we recommend user select SSMs and topN with relative high scores in both AUC and ES for later query in Application module. For example, topN in the top 10 of result ES and AUC is acceptable.**  
**if you want to use SS_cross, it is important to note that we recommend each oncogenic signature be evaluated in the Benchmark module. If the optimal topN and SSM for two oncogenic signatures are identical or close (with high scores in the same topN or a high ranking in SSM), this indicates a strong match. If not, it is advisable to replace the oncogenic signatures.** 
**if you want to use SS_all, just select the SSMs with high performance over minority in AUC.**   
