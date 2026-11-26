#############################################################
# DESAFIO DE DADOS - MENSURACAO FLORESTAL
# Talhao 8 - Eucalipto - Inventario Florestal
#
# Analise de auditoria e caracterizacao do DAP de um inventario
# florestal real (6 parcelas, 215 arvores). Interpretacao completa
# dos resultados em docs/relatorio.pdf. Executar a partir da raiz:
#   Rscript scripts/01_analise_diametro.R
#############################################################

library(readxl)
library(dplyr)
library(ggplot2)

dir.create("resultados/tabelas", recursive = TRUE, showWarnings = FALSE)
dir.create("resultados/figuras", recursive = TRUE, showWarnings = FALSE)

# ===== Etapa 0: leitura e auditoria basica dos dados =====

inventario <- read_excel("dados/inventario.xlsx")

dim(inventario)               # esperado: 215 linhas, 14 colunas
colSums(is.na(inventario))    # esperado: zero NA em cada coluna
table(inventario$PARCELA)     # esperado: 37,36,37,41,32,32


# ===== Questao 1: estatisticas descritivas do DAP =====

estat_parcela <- inventario %>%
  group_by(PARCELA) %>%
  summarise(
    n         = n(),
    dap_medio = mean(DAP),
    dap_quad  = sqrt(mean(DAP^2)),   # diametro medio quadratico (dg)
    dap_dp    = sd(DAP),
    dap_min   = min(DAP),
    dap_max   = max(DAP),
    dap_cv    = (dap_dp / dap_medio) * 100
  )
estat_parcela

estat_talhao <- inventario %>%
  summarise(
    n         = n(),
    dap_medio = mean(DAP),
    dap_quad  = sqrt(mean(DAP^2)),
    dap_dp    = sd(DAP),
    dap_min   = min(DAP),
    dap_max   = max(DAP),
    dap_cv    = (dap_dp / dap_medio) * 100
  )
estat_talhao


# ===== Questao 2 (parte 1): classes de diametro =====
# Amplitude de classe = desvio-padrao do respectivo grupo

construir_tabela_classes <- function(dap, amplitude) {
  minimo <- min(dap)
  maximo <- max(dap)
  n_classes <- ceiling((maximo - minimo) / amplitude)
  limites <- minimo + (0:n_classes) * amplitude

  classes <- cut(dap, breaks = limites, right = FALSE, include.lowest = TRUE)

  tabela <- as.data.frame(table(classes))
  names(tabela) <- c("classe", "freq_abs")
  tabela$freq_acum         <- cumsum(tabela$freq_abs)
  tabela$freq_rel_pct      <- (tabela$freq_abs / sum(tabela$freq_abs)) * 100
  tabela$freq_rel_acum_pct <- cumsum(tabela$freq_rel_pct)
  tabela
}

tabelas_classes_parcela <- inventario %>%
  group_by(PARCELA) %>%
  group_modify(~ construir_tabela_classes(.x$DAP, sd(.x$DAP)))
tabelas_classes_parcela

tabela_classes_talhao <- construir_tabela_classes(inventario$DAP, sd(inventario$DAP))
tabela_classes_talhao

# estimativa de arvores DAP>=15cm no talhao -> ver retomada apos Questao 6


# ===== Questao 4: auditoria - deteccao de valores suspeitos no DAP =====
# Criterio: IQR por parcela (principal) + escore-z por parcela (complementar)
# Justificativa completa do criterio em README.md

deteccao_outliers <- inventario %>%
  group_by(PARCELA) %>%
  mutate(
    q1 = quantile(DAP, 0.25),
    q3 = quantile(DAP, 0.75),
    iqr = q3 - q1,
    limite_inf = q1 - 1.5 * iqr,
    limite_sup = q3 + 1.5 * iqr,
    suspeito_iqr = DAP < limite_inf | DAP > limite_sup,
    z_score = (DAP - mean(DAP)) / sd(DAP),
    suspeito_z = abs(z_score) > 2
  ) %>%
  ungroup()

suspeitos <- deteccao_outliers %>%
  filter(suspeito_iqr | suspeito_z) %>%
  select(PARCELA, FILEIRA, `ÁRVORE`, DAP, limite_inf, limite_sup, z_score,
         suspeito_iqr, suspeito_z)
suspeitos

# Nenhum valor removido: sinalizados sao arvores dominadas plausiveis,
# nao erros de medicao/digitacao (ver README.md).


# ===== Questao 6: area da parcela e arvores/ha (espacamento 3x3 m) =====
# Premissa: a fileira com mais arvores observadas representa o comprimento
# "de projeto" da parcela (nao afetado por falha de plantio)

n_fileiras  <- 7
espacamento <- 3  # metros

max_arv_fileira <- inventario %>%
  group_by(PARCELA, FILEIRA) %>%
  summarise(n_arv = n(), .groups = "drop") %>%
  group_by(PARCELA) %>%
  summarise(max_arv_fileira = max(n_arv))

area_parcela <- max_arv_fileira %>%
  mutate(
    area_m2 = n_fileiras * espacamento * max_arv_fileira * espacamento,
    area_ha = area_m2 / 10000
  )
area_parcela

arvores_ha <- inventario %>%
  group_by(PARCELA) %>%
  summarise(n_arv_parcela = n()) %>%
  left_join(area_parcela, by = "PARCELA") %>%
  mutate(arv_ha = n_arv_parcela / area_ha)
arvores_ha

mean(arvores_ha$arv_ha)   # densidade media do talhao (arv/ha)


# ===== Questao 3: area basal (m2) e area basal por hectare =====

inventario <- inventario %>%
  mutate(g = (pi/4) * (DAP/100)^2)   # area basal individual, m2 (DAP em cm)

g_parcela <- inventario %>%
  group_by(PARCELA) %>%
  summarise(area_basal_m2 = sum(g))
g_parcela

g_parcela_ha <- g_parcela %>%
  left_join(area_parcela, by = "PARCELA") %>%
  mutate(area_basal_m2_ha = area_basal_m2 / area_ha)
g_parcela_ha

sum(inventario$g)                          # area basal total amostrada (m2)
mean(g_parcela_ha$area_basal_m2_ha)        # area basal media do talhao (m2/ha)


# ===== Retomando a Questao 2 (parte 2): DAP>=15cm no talhao (48,7 ha) =====

n15_parcela <- inventario %>%
  filter(DAP >= 15) %>%
  group_by(PARCELA) %>%
  summarise(n_dap15 = n()) %>%
  left_join(area_parcela, by = "PARCELA") %>%
  mutate(dap15_ha = n_dap15 / area_ha)
n15_parcela

area_talhao_ha <- 48.7
media_dap15_ha <- mean(n15_parcela$dap15_ha)
media_dap15_ha * area_talhao_ha   # estimativa total de arvores DAP>=15cm


# ===== Questao 5: histograma da distribuicao diametrica =====
# Curva normal teorica sobreposta como referencia visual de simetria

media_dap <- mean(inventario$DAP)
dp_dap    <- sd(inventario$DAP)

ggplot(inventario, aes(x = DAP)) +
  geom_histogram(aes(y = after_stat(density)), binwidth = sd(inventario$DAP),
                  fill = "seagreen", color = "white", alpha = 0.7,
                  boundary = min(inventario$DAP)) +
  stat_function(fun = dnorm, args = list(mean = media_dap, sd = dp_dap),
                color = "firebrick", linewidth = 1) +
  labs(title = "Distribuicao diametrica - Talhao 8 (com curva normal teorica)",
       x = "DAP (cm)", y = "Densidade") +
  theme_minimal()

ggsave("resultados/figuras/histograma_talhao.png", width = 8, height = 5, dpi = 300, bg = "white")

stats_por_parcela <- inventario %>%
  group_by(PARCELA) %>%
  summarise(media = mean(DAP), dp = sd(DAP))

curvas_normais <- stats_por_parcela %>%
  group_by(PARCELA) %>%
  reframe(
    DAP = seq(media - 4 * dp, media + 4 * dp, length.out = 200),
    densidade = dnorm(DAP, mean = media, sd = dp)
  )

ggplot(inventario, aes(x = DAP)) +
  geom_histogram(aes(y = after_stat(density)), binwidth = 2,
                  fill = "steelblue", color = "white", alpha = 0.7) +
  geom_line(data = curvas_normais, aes(x = DAP, y = densidade),
            color = "firebrick", linewidth = 1) +
  facet_wrap(~ PARCELA, ncol = 3) +
  labs(title = "Distribuicao diametrica por parcela - Talhao 8 (com curva normal)",
       x = "DAP (cm)", y = "Densidade") +
  theme_minimal()

ggsave("resultados/figuras/histograma_parcelas.png", width = 9, height = 6, dpi = 300, bg = "white")


# ===== Exportacao das tabelas principais =====
write.csv(estat_parcela, "resultados/tabelas/estatisticas_dap_parcela.csv", row.names = FALSE)
write.csv(estat_talhao,  "resultados/tabelas/estatisticas_dap_talhao.csv",  row.names = FALSE)
write.csv(tabela_classes_talhao, "resultados/tabelas/classes_dap_talhao.csv", row.names = FALSE)
write.csv(g_parcela_ha,  "resultados/tabelas/area_basal_parcela.csv", row.names = FALSE)
