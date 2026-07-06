load("sessioninfo.rdata")

# 请确认网络环境都正常

for (pkg in sI){
  if (! require(pkg,character.only=T) ) {
    BiocManager::install(pkg,ask = F,update = F)
    require(pkg,character.only=T) 
  }
}

for (pkg in sI){
  if (! require(pkg,character.only=T) ) {
    install.packages(pkg,ask = F,update = F)
    require(pkg,character.only=T) 
  }
}

#前面的所有提示和报错都先不要管。主要看这里
for (pkg in sI){
  require(pkg,character.only=T) 
}

dir.create("cache")
dir.create("cache/BM")
dir.create("cache/SM")
dir.create("cache/SS")



