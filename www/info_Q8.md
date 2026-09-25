### How to query drugs if I have other type signature?
SSP is designed to find promising drug based on oncogenic signature and drug annotation.
**With the adoption of LINCS for applications beyond oncology, SSP could potentially be adapted for other disease signatures.**   
However, careful investigation is warranted, and responsibility for the accuracy of results obtained through this method is not assumed.    
**Similarly, within the robustness module, drug-self retrieval is utilized to assess the SSM, suggesting that SSP could also be applicable to drug signatures in Benchmark, albeit with slight differences.**    
**In this context, drug signatures can facilitate the discovery of new uses for existing drugs, while SS_cross can be employed to identify drugs with multiple activities.**  
For instance, it is necessary to accurately annotate drugs labeled 'Ineffective' that are in fact effective, and vice versa, when preparing for AUC. Additionally, a list of effective drugs must be provided for ES, where a higher ES indicates superior performance.  
**Robustness module** is **not affected** because it is inherently based on the results obtained from drug signature self-retrieval.   
However,again, careful investigation is warranted, and responsibility for the accuracy of results obtained through this method is not assumed.
