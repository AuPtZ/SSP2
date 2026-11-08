### Converter (for Drug)

SSP2 annotates drugs by **drug name** - the identifier of a drug in SSP2 is the
`Compound_name`. If your list uses another identifier (**SMILES(Canonical)**,
**PubChem Cid**, **InChIKeys** or **CMAP ID (BRD-)**), convert it here first: paste your
list in the left panel, choose the identifier type and click **Convert**; the converted
drug names are shown immediately on the right.

**Please note that the Converter module only returns drugs that are within the PTDs.**

<div style="padding: 6px; text-align: center;">
<img src="imgct_new_d.png" width="34%" alt="Drug identifier conversion panel" />
</div>

Here are some tips:

1. The Converter accepts a drug list with **no more than 1000 rows**.
2. **SSP2 accepts a one-column list or a two-column tab-separated table.** A one-column list
   is recommended: the output contains a single `Compound_name` column, which is exactly the
   drug-annotation format required by the Benchmark page. If you supply a second column, it
   is carried through as `Group` for your own records, but it is not used by the Benchmark
   calculation - whether the drugs are effective or toxic is chosen with the radio buttons
   on the Benchmark page.
3. If you input drug names and select **Drug Name**, SSP2 will try to correct the names
   **(capitalization and spaces)** to match the inner-built pharmacotranscriptomic datasets.
   This is very useful when the drug information was collected on your own.
4. The three **demo** buttons load an example list for each supported identifier type.

In addition, we also provide a gene converter; you can access the sub-module by clicking on
the **Gene** tab.
