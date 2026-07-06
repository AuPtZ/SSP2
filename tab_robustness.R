### 交互相应区域

# 初始化
output$display_rb <- renderUI(initial_rb)

# 重置
observeEvent(input$reset_rb, {
  reset("rb_input")
  output$display_rb <- renderUI(initial_rb)
})

# 输出
observeEvent(input$runRB, {
  isolate({
    output$display_rb <- renderUI({
      isolate({
        dir_rb = paste0("data_preload/robustness/",input$sel_experiment_rb) 
        to_rb <- get_rb_plot(dir_rb, input$sel_ss_rb)

        pic_out <- to_rb$pic_out
        res_rb <- to_rb$res_rb
        DT_res_rb <- datatable(res_rb) %>% 
          formatStyle(names(res_rb)[which.max(res_rb[1,-1]) + 1],
                      backgroundColor = styleEqual(res_rb[1, which.max(res_rb[1,-1])+ 1], c('yellow')))
      })
      tagList(
        shiny::h3("Robustness score",actionButton("intro_res_rb","Quick Tip",class = "btn-success")),
        renderPlotly(pic_out),
        DT::renderDataTable(DT_res_rb)
      )
    })
  })
})


initial_rb <- tagList(
  withMathJax(),
  includeMarkdown("www/tab_robustness.md")
  
)
