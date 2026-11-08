### How to query drugs if I have other type signature?
SSP2 is designed to find promising drugs based on a query signature and a compound annotation.
**With the adoption of LINCS for applications beyond oncology, SSP2 could potentially be adapted for other disease signatures.**
Careful investigation is warranted, and responsibility for the accuracy of results obtained through this method is not assumed.
**In Benchmark, drug signatures can facilitate the discovery of new uses for existing drugs, while SS_cross can be employed to identify drugs with multiple activities.**

For any signature type, the Benchmark annotation is a **one-column list** of drug names
(header `Compound_name`): the drugs your signature is expected to retrieve. On the
Benchmark page, choose what this list means with the radio buttons - **Effective drugs**
(efficacy benchmark) or **Toxic drugs** (toxicity screening). SSP2 then evaluates how well
each signature search method ranks these drugs using five ranking-quality metrics against a
label-permutation null; no `Group` column or `Effective` / `Ineffective` labels are needed.
A blank one-column template listing all drugs in the selected dataset can be downloaded
from Step 1 of the Benchmark page.

Here again, careful investigation is warranted, and responsibility for the accuracy of
results obtained through this method is not assumed.
