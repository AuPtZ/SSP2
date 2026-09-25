# Pure helper: write benchmark / application results to the SQLite database
# No input/output dependencies; the calling module constructs the metadata df1.
db_write_result <- function(Jobid, Submitted_time, module_name, sub_module,
                            table_num, table_res, df1) {
  con_res <- RSQLite::dbConnect(RSQLite::SQLite(), "results/resinfo.db")
  on.exit(RSQLite::dbDisconnect(con_res))

  if (table_num == 1) {
    RSQLite::dbWriteTable(con_res, Jobid, table_res)
    RSQLite::dbAppendTable(con_res, "res", df1)
  } else if (table_num == 2) {
    RSQLite::dbWriteTable(con_res, paste0(Jobid, "_AUC"), table_res[["AUC"]])
    RSQLite::dbWriteTable(con_res, paste0(Jobid, "_ES"), table_res[["ES"]])
    RSQLite::dbAppendTable(con_res, "res", df1)
  }
}
