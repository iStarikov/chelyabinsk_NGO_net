setwd("D:/2017/R net analysis")
load("D:/2017/R net analysis/Челябинск/che74.RData")

library("RCurl") # Библиотека для генерации запросов к API
library("jsonlite") # Библиотека для обработки JSON
library(igraph) # Библиотека для создание данных для построения графа
library(dplyr)# Библиотека для создание данных для построения графа
library(tidyr)
library(stringr)
library(ggplot2)
library(curl)
library(microbenchmark)

#редактирование БД
gr_che <- read.csv("Челябинск/che74_fixed.csv", sep = ";", stringsAsFactors = F) #encoding = "UTF-8"
gr_che <- gr_che[, -2]
gr_che$url_VK <- gsub("http://vk.com/", "", gr_che$url_VK)
gr_che$url_VK <- gsub("https://vk.com/", "", gr_che$url_VK)
gr_che$url_VK <- str_trim(gr_che$url_VK)

x_club <- grep("club", gr_che$url_VK)
gr_che$url_VK[x_club] <- gsub("club", "", gr_che$url_VK[x_club])

x_club <- grep("event", gr_che$url_VK)
gr_che$url_VK[x_club] <- gsub("event", "", gr_che$url_VK[x_club])

x_club <- grep("public", gr_che$url_VK)
gr_che$url_VK[x_club] <- gsub("public", "", gr_che$url_VK[x_club])


# выкачка данных
url <- "https://api.vk.com/method/groups.getMembers?group_id=" # базовый url для работы с API VK
# count members in groups
#url_get <- paste0("https://api.vk.com/method/groups.getMembers?group_id=", "event67003902")

get_count_memb <- function(id) {
  url_get <- paste0(url, id) # Составляем запрос к API
  resp <- getURL(url_get) # Запрашиваем и получаем ответ
  Sys.sleep(0.34) # Задержка для обхода ограничения на кол-во запросов в сек
  # Обрабатываем ответ и получаем id подписок
  fromJSON(resp)$response$count
}

# count members for groups in gr_che
system.time({
member_count <- sapply(gr_che$url_VK, get_count_memb)
})
View(as.data.frame(member_count))
gr_che$group_size_VK_T <- member_count


View(gr_che[, c('group_size_VK_T', 'group_size_VK_T2')])
sum(abs(gr_che$group_size_VK_T - gr_che$group_size_VK_T2)> 20)
gr_che[abs(gr_che$group_size_VK_T - gr_che$group_size_VK_T2)> 20,
            c('group_size_VK_T', 'group_size_VK_T2')]

get_id_memb <- function(group_URL) {
  #url_get <- paste0(url, id) # Составляем запрос к API
  resp <- getURL(group_URL) # Запрашиваем и получаем ответ
  Sys.sleep(0.34) # Задержка для обхода ограничения на кол-во запросов в сек
  # Обрабатываем ответ и получаем id подписок
  fromJSON(resp)$response$users
}

# супер функция, для возвращения ид участников группы

get_group_users <- function(group) {
  url1 <- "https://api.vk.com/method/groups.getMembers?group_id="
  print(paste0("Quering group ", group))
  # Узнаем количество участников
  resp <- getURL(paste0(url1, group)) # Составляем запрос к API
  Sys.sleep(0.34) # Задержка для обхода ограничения на кол-во запросов в сек
  group_members_count <- fromJSON(resp)$response$count
  print(group_members_count)
  
  # Получаем ид участников
  x <- character()
  for(i in 0:floor(group_members_count/1000)){
    print(paste0("Getting chunk ", i))
    group_URL <- paste0(url1, group, "&offset=", 1000*i)
    x <- append(x, get_id_memb(group_URL))
  }
  return(x)
}

                  #### МНОГОПОТОЧНОСТЬ ####
###
library(foreach)
library(doParallel)    
cl <- makeCluster(detectCores())    # Создаем «кластер» на восемь потоков
registerDoParallel(cl)


stopCluster(cl) # останавливаем кластер

group_url <- gr_che$url_VK

length(unique(gr_che$url_VK))

system.time({
  member_count_dopar <- foreach(j=1:length(group_url), .packages = c("RCurl", "jsonlite")) %dopar% get_count_memb(group_url[j]) # 
})

gr_che$group_size_VK_T2 <- unlist(member_count_dopar)


system.time({
  users <- foreach(j=1:length(group_url), .packages = c("RCurl", "jsonlite")) %dopar% get_group_users(group_url[j]) # 
})
names(users) <- gr_che$short_name

x <- sapply(1:length(users), function(j) length(users[[j]]))

all.equal(gr_che$group_size_VK_T2, x)
which(abs(x - gr_che$group_size_VK_T2)==1)
                  

system.time({
users <- sapply(gr_che$url_VK, function(x) get_group_users(x)) 
})

all.users <- c(users, recursive = T)
uniq.users <- unique(all.users)

table(gr_che$gov)

#### для создания сети только по тем группам которые занимаются гор средой или для подсчета только тех людей, которые занимаются гор средой
table(gr_che$physic_environment)
table(gr_che$urban_improve)


# лист только с теми, кто как-то связан с изменением городской среды
urban_users <- users[gr_che$url_VK[gr_che$physic_environment %in% 
                                     c(4, 5) |
                                     gr_che$urban_improve == 1]]

all.urb_users <- c(urban_users, recursive = T)
uniq.urb_users <- unique(all.urb_users)
# всего в Челябинске уникальных пользователей, которые состоят в группах, посвященных 
# изменениеям в городской среде или в группах, которые занимаются проектами по изменнию гор среды
# состоит 144841 человек, среди них можно построить сеть.

### count not goverment users
not_gov_users <- users[which(gr_che$gov %in% "not_gov")]
not_gov_users <- unique(c(not_gov_users, recursive = T))

#not_gov_users <- not_gov_users[gr_che$name[gr_che$physic_environment %in% c("prob_yes","yes") |
#                      gr_che$urban_improve == "urban_project"]]




### для редактирования запишем файл csv и подправим его.
#write.csv(x = gr_che, "Челябинск/che74_for_fix.csv")



###
### СОЗДАЕМ ФАЙЛ ДЛЯ SNA
## Можно использовать меру Жаккара, но об этом чуть позже
### пока собственная мера для формирвоания ориентированного графа, что позволяет учитывать не общую связь между группами, а именно пересечение данных групп


intersect.mat <- matrix(0, nrow = length(users), ncol = length(users))
for(i in 1:nrow(intersect.mat))
  for(j in 1:ncol(intersect.mat))
    intersect.mat[i, j] <- length(intersect(users[[i]], users[[j]]))/length(users[[j]])
# диагональ должна быть равна 0
diag(intersect.mat) <- 0

# решаем как избавится от волосатых шаров - слишком сильных пересечений между всеми группами
which.max(apply(intersect.mat, 1, median))
hist(intersect.mat[80,], breaks=50)
median(intersect.mat[80,])

hist(apply(intersect.mat, 1, median), breaks=40)

vec_int.mat <- as.vector(intersect.mat)
hist(as.vector(intersect.mat), breaks = 40)
median(vec_int.mat)



inf_vec <- function(x){
  hist(x, breaks = 80)
  print(paste("length", length(x)))
  print(quantile(x, probs = c(0.05, 0.1, 0.15, 0.2, 0.25)))
  print(paste("median", median(x)))
}


inf_vec(vec_int.mat[vec_int.mat > 0.1 ])

sd(vec_int.mat)
median(vec_int.mat)
hist(unlist(member_count_dopar), breaks = 40)
gr_che$name[80]

5/1000

# 5% будет оптимальным значением пересечений до которого мы считаем пересечения случайными, 
# тогда мы используем около  % наших связей 
cut <- 0.1
intersect.mat.cut <- apply(intersect.mat, 1, function(x){
  x[x < cut] <- 0
  x})

names(gr_che)
#добавляем параметры
gr_che$grant_part <- ifelse(gr_che$grant_part %in% 1, "grant_part", "not_grant_part")
gr_che$grant_win <- ifelse(gr_che$grant_win %in% 1, "grant_win", "not_grant_win")

#пропровительственные 
#gr_che$progov[is.na(gr_che$gov)] <- c(0,0,2,2)
gr_che$gov <- as.factor(gr_che$gov)
levels(gr_che$gov) <- c("not_gov", "gov")

# цели в сфере изменнеия городской физической среды
gr_che$physic_environment <- as.factor(gr_che$physic_environment)
levels(gr_che$physic_environment) <- c("not", "prob_not", "prob_yes", "yes")

# опыт в изменнеии городской физ среды
gr_che$urban_improve[gr_che$urban_improve %in% "1"] <- "urban_project"
gr_che$urban_improve[gr_che$urban_improve %in% "0"] <- "no_info"

# протестная деятельность
gr_che$revolt[gr_che$revolt %in% "1"] <- "revolt"
gr_che$revolt[gr_che$revolt %in% "0"] <- "not_revolt"

gr_che$eco <- ifelse(gr_che$eco %in% 1, "eco", "not_eco")
gr_che$commerce <- ifelse(gr_che$commerce %in% 1, "for_$", "not_for_$")
gr_che$is.NGO <- ifelse(gr_che$is.NGO %in% 1, "NGO", "not_NGO")



is.NGO <- gr_che$is.NGO
grant_win <- gr_che$grant_win
grant_part <- gr_che$grant_part
prof_eco <- gr_che$eco
prof_commerce <- gr_che$commerce
prof_physic_target <- as.character(gr_che$physic_environment)
prof_urban_project <- gr_che$urban_improve
prof_gov <- as.character(gr_che$gov)
prof_revolt <- gr_che$revolt


  colnames(intersect.mat.cut) <- rownames(intersect.mat.cut) <- gr_che$short_name

int.graph <- graph_from_adjacency_matrix(intersect.mat.cut,
                                         mode = "directed",
                                         weighted = T)


int.graph <- set_vertex_attr(int.graph, "group_size", value = unlist(member_count_dopar))
int.graph <- set_vertex_attr(int.graph, "gov", value = prof_gov)
int.graph <- set_vertex_attr(int.graph, "urban_project", value = prof_urban_project)
int.graph <- set_vertex_attr(int.graph, "grant_win", value = grant_win)
int.graph <- set_vertex_attr(int.graph, "grant_part", value = grant_part)
int.graph <- set_vertex_attr(int.graph, "physic_target", value = prof_physic_target)
int.graph <- set_vertex_attr(int.graph, "revolt", value = prof_revolt)
int.graph <- set_vertex_attr(int.graph, "eco", value = prof_eco)
int.graph <- set_vertex_attr(int.graph, "commerce", value = prof_commerce)
int.graph <- set_vertex_attr(int.graph, "lable_NGO", value = gr_che$short_name)
int.graph <- set_vertex_attr(int.graph, "is_NGO", value = is.NGO)
int.graph <- set_vertex_attr(int.graph, "walktrap.community", value = paste0("cl_wtrap", walktrap.community(int.graph)$membership))


# записываем файл с которым будем работать в Гефи
write_graph(int.graph, "Челябинск/che_graph_new.graphml", format = "graphml")

mean(c(member_count_dopar))

# кластеризация
####
#### https://www.sixhat.net/finding-communities-in-networks-with-r-and-igraph.html
#### http://www.nickeubank.com/wp-content/uploads/2015/10/RGIS6_networkanalysis.html#community-detection
#### http://igraph.org/r/doc/cluster_louvain.html
#### http://igraph.org/r/doc/cluster_optimal.html
#### http://igraph.org/r/doc/plot_dendrogram.communities.html (the good one)
#### https://rpubs.com/gaston/dendrograms (don't know for what)

x2 <- walktrap.community(int.graph, modularity = T, steps = 5)
length(unique(x2$membership))


plot_dendrogram(x2, mode = igraph_opt("dend.plot.type"),
                use.modularity = T)

plot_dendrogram(x2, mode="hclust", rect = 0, colbar = palette(),
                hang = -1, ann = FALSE, main = "", sub = "", xlab = "",
                ylab = "")

plot_dendrogram(x2, mode="phylo", type = "fan", cex = 0.6, 
                use.edge.length = TRUE, label.offset = 1)

plot_dendrogram(x2, mode="phylo", cex = 0.4,
                use.edge.length = T, label.offset = 1, 
                palette = my_palette)

# for colors - is's for palett
my_palette <- c("#9f49c3", "#5fb348", "#6066e0", "#b6b343", "#be79e7","#d38c30",
                "#4576d5","#cc5033","#45c0bc","#c73b93","#53a36f","#e46fcc","#757b32",
                "#7452af","#c07e55","#928ee5","#db4269","#5da2d9","#a0495f","#5b69a8",
                "#e0829f", "#964f95", "#c590d2")

# colorRampPalette(c("blue", "red"))(23)

plot_dendrogram(x2, mode="phylo", type = "unrooted", cex = 0.1, 
                use.edge.length = T, label.offset = 0.1)



#### что-то пробую
####
find.clusters((intersect.mat.cut*(-1)+1), criterion = "smoothNgoesup")

library(adegenet)

# посик кластеров в графе
g <- make_full_graph(5) %du% make_full_graph(5) %du% make_full_graph(5)
g <- add_edges(g, c(1,6, 1,11, 6, 11))
cluster_louvain(g)
vertex_size <- (gr_che$group_size_VK-min(gr_che$group_size_VK))/(max(gr_che$group_size_VK)-min(gr_che$group_size_VK))


g <- int.graph
int.graph$layout <- layout.fruchterman.reingold
plot(int.graph, xlim = c(-0.4, 0.6), ylim = c(-0.5, 0.5), 
     vertex.size = 5, # vertex_size*10
     vertex.label = NA,
     edge.arrow.size = 0.2,
     edge.curved = T)


ebc <- edge.betweenness.community(int.graph, directed=T)
mods <- sapply(0:ecount(int.graph), function(i){
  g2 <- delete.edges(int.graph, ebc$removed.edges[seq(length=i)])
  cl <- clusters(g2)$membership
  # March 13, 2014 - compute modularity on the original graph g 
  # (Thank you to Augustin Luna for detecting this typo) and not on the induced one g2. 
  modularity(int.graph,cl)
})

plot(mods, pch=20)

g2<-delete.edges(int.graph, ebc$removed.edges[seq(length=which.max(mods)-1)])
V(int.graph)$color=clusters(g2)$membership


                      ##############
                    # для меры Жаккара #
                      ##############


intersect.mat_kj <- matrix(0, nrow = length(users), ncol = length(users))
for(i in 1:nrow(intersect.mat_kj)){
  for(j in i:ncol(intersect.mat_kj)){
    common <- length(intersect(users[[i]], users[[j]]))
    all <- length(c(users[c(i,j)], recursive = T))
    intersect.mat_kj[i,j] <-  common/(all - common)
}}
# диагональ должна быть равна 0
diag(intersect.mat_kj) <- 0
intersect.mat_kj %>% 
  View()

intersect.mat_kj.cut <- apply(intersect.mat_kj, 1, function(x){
  x[x < cut] <- 0
  x})


colnames(intersect.mat_kj.cut) <- rownames(intersect.mat_kj.cut) <- gr_che$short_name 

int.graph_kj <- graph_from_adjacency_matrix(intersect.mat_kj.cut,
                                         mode = "undirected",
                                         weighted = T)


int.graph_kj <- set_vertex_attr(int.graph_kj, "group_size", value = unlist(member_count_dopar))
int.graph_kj <- set_vertex_attr(int.graph_kj, "gov", value = prof_gov)
int.graph_kj <- set_vertex_attr(int.graph_kj, "urban_project", value = prof_urban_project)
int.graph_kj <- set_vertex_attr(int.graph_kj, "grant_win", value = grant_win)
int.graph_kj <- set_vertex_attr(int.graph_kj, "grant_part", value = grant_part)
int.graph_kj <- set_vertex_attr(int.graph_kj, "physic_target", value = prof_physic_target)
int.graph_kj <- set_vertex_attr(int.graph_kj, "revolt", value = prof_revolt)
int.graph_kj <- set_vertex_attr(int.graph_kj, "eco", value = prof_eco)
int.graph_kj <- set_vertex_attr(int.graph_kj, "commerce", value = prof_commerce)
int.graph_kj <- set_vertex_attr(int.graph_kj, "lable_NGO", value = gr_che$short_name)
int.graph_kj <- set_vertex_attr(int.graph_kj, "is_NGO", value = is.NGO)

int.graph_kj <- set_vertex_attr(int.graph_kj, "louvain_com", value = paste0("cl_louv", x1$membership))
int.graph_kj <- set_vertex_attr(int.graph_kj, "walktrap.community", value = paste0("cl_wtrap", x2$membership))
int.graph_kj <- set_vertex_attr(int.graph_kj, "fastgreedy.community", value = paste0("cl_fgreedy", xa$membership))
int.graph_kj <- set_vertex_attr(int.graph_kj, "spinglass.community", value = paste0("cl_spglass", x3$membership))



write_graph(int.graph_kj, "Челябинск/che_graph_kj.graphml", format = c("graphml"))
write.csv(gr_che[, c("group_size_VK_T", "short_name")], "Челябинск/che_kj.csv")

x <- fastgreedy.community(int.graph_kj)

x1 <- cluster_louvain(int.graph_kj)

x3 <- walktrap.community(int.graph_kj)

x4 <- spinglass.community(int.graph_kj)

all.equal(as.vector(membership(x1)), x1$membership)

cbind(x1$membership, x$membership) %>% 
  as.data.frame() %>% 
  arrange(V1, V2) %>% 
  View()

louvain.communitys <- as.data.frame(cbind(names(membership(x1)), membership(x1)))
names(louvain.communitys) <- c("name", "group_assignment")

as.dendrogram(x2, hang = -1,
              use.modularity = FALSE)

plot_dendrogram(x2, mode = igraph_opt("dend.plot.type"),
                use.modularity = F)

plot_dendrogram(x2, mode="hclust", rect = 0, colbar = palette(),
                hang = -1, ann = FALSE, main = "", sub = "", xlab = "",
                ylab = "")

plot_dendrogram(x2, mode="phylo", type = "fan", cex = 0.6, 
                use.edge.length = TRUE, label.offset = 1)

plot_dendrogram(x2, mode="phylo", cex = 0.4,
                use.edge.length = F, label.offset = 1)


plot_dendrogram(x2, mode="phylo", type = "unrooted", cex = 0.1, 
                use.edge.length = T, label.offset = 0.1)



#save.image("D:/2017/R net analysis/Челябинск/che74.RData")
