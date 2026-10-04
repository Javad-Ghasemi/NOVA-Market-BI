USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'meta.ProductCategoryLocalization', N'U') IS NULL
BEGIN
    CREATE TABLE meta.ProductCategoryLocalization
    (
        SourceCategoryName VARCHAR(100) NOT NULL,
        PersianCategoryName NVARCHAR(100) NOT NULL,

        CONSTRAINT PK_meta_ProductCategoryLocalization
            PRIMARY KEY (SourceCategoryName)
    );
END;
GO

TRUNCATE TABLE meta.ProductCategoryLocalization;
GO

INSERT INTO meta.ProductCategoryLocalization
(
    SourceCategoryName,
    PersianCategoryName
)
VALUES
('agro_industria_e_comercio', N'صنعت و تجارت کشاورزی'),
('alimentos', N'مواد غذایی'),
('alimentos_bebidas', N'مواد غذایی و نوشیدنی'),
('artes', N'هنر'),
('artes_e_artesanato', N'هنر و صنایع دستی'),
('artigos_de_festas', N'لوازم مهمانی'),
('artigos_de_natal', N'لوازم کریسمس'),
('audio', N'صوتی'),
('automotivo', N'خودرو'),
('bebes', N'نوزاد'),
('bebidas', N'نوشیدنی‌ها'),
('beleza_saude', N'سلامت و زیبایی'),
('brinquedos', N'اسباب‌بازی'),
('cama_mesa_banho', N'کالای خواب، حمام و میز'),
('casa_conforto', N'آسایش خانه'),
('casa_conforto_2', N'آسایش خانه ۲'),
('casa_construcao', N'ساخت‌وساز خانه'),
('cds_dvds_musicais', N'سی‌دی و دی‌وی‌دی موسیقی'),
('cine_foto', N'سینما و عکاسی'),
('climatizacao', N'تهویه مطبوع'),
('consoles_games', N'کنسول و بازی'),
('construcao_ferramentas_construcao', N'ابزار ساخت‌وساز'),
('construcao_ferramentas_ferramentas', N'ابزارآلات ساختمانی'),
('construcao_ferramentas_iluminacao', N'روشنایی ساختمانی'),
('construcao_ferramentas_jardim', N'ابزار باغبانی'),
('construcao_ferramentas_seguranca', N'تجهیزات ایمنی ساختمانی'),
('cool_stuff', N'کالاهای خاص'),
('dvds_blu_ray', N'دی‌وی‌دی و بلوری'),
('eletrodomesticos', N'لوازم خانگی'),
('eletrodomesticos_2', N'لوازم خانگی ۲'),
('eletronicos', N'الکترونیک'),
('eletroportateis', N'لوازم برقی کوچک'),
('esporte_lazer', N'ورزش و اوقات فراغت'),
('fashion_bolsas_e_acessorios', N'مد، کیف و اکسسوری'),
('fashion_calcados', N'مد و کفش'),
('fashion_esporte', N'مد ورزشی'),
('fashion_roupa_feminina', N'پوشاک زنانه'),
('fashion_roupa_infanto_juvenil', N'پوشاک کودک و نوجوان'),
('fashion_roupa_masculina', N'پوشاک مردانه'),
('fashion_underwear_e_moda_praia', N'لباس زیر و لباس ساحلی'),
('ferramentas_jardim', N'ابزار باغبانی'),
('flores', N'گل'),
('fraldas_higiene', N'پوشک و بهداشت'),
('industria_comercio_e_negocios', N'صنعت، تجارت و کسب‌وکار'),
('informatica_acessorios', N'رایانه و لوازم جانبی'),
('instrumentos_musicais', N'سازهای موسیقی'),
('la_cuisine', N'لوازم آشپزخانه'),
('livros_importados', N'کتاب‌های وارداتی'),
('livros_interesse_geral', N'کتاب‌های عمومی'),
('livros_tecnicos', N'کتاب‌های تخصصی'),
('malas_acessorios', N'چمدان و لوازم جانبی'),
('market_place', N'بازارگاه'),
('moveis_colchao_e_estofado', N'مبلمان، تشک و اثاثیه روکش‌دار'),
('moveis_cozinha_area_de_servico_jantar_e_jardim', N'مبلمان آشپزخانه، غذاخوری، رختشویی و باغ'),
('moveis_decoracao', N'مبلمان و دکوراسیون'),
('moveis_escritorio', N'مبلمان اداری'),
('moveis_quarto', N'مبلمان اتاق خواب'),
('moveis_sala', N'مبلمان پذیرایی'),
('musica', N'موسیقی'),
('papelaria', N'لوازم‌التحریر'),
('pc_gamer', N'رایانه گیمینگ'),
('pcs', N'رایانه'),
('perfumaria', N'عطر و ادکلن'),
('pet_shop', N'لوازم حیوانات خانگی'),
('portateis_casa_forno_e_cafe', N'لوازم برقی کوچک خانه، فر و قهوه'),
('portateis_cozinha_e_preparadores_de_alimentos', N'لوازم کوچک آشپزخانه و آماده‌سازی غذا'),
('relogios_presentes', N'ساعت و هدایا'),
('seguros_e_servicos', N'امنیت و خدمات'),
('sinalizacao_e_seguranca', N'علائم و تجهیزات ایمنی'),
('tablets_impressao_imagem', N'تبلت، چاپ و تصویر'),
('telefonia', N'تلفن و ارتباطات'),
('telefonia_fixa', N'تلفن ثابت'),
('utilidades_domesticas', N'لوازم خانه');
GO


SELECT
    COUNT(*) AS [LocalizationRows],

    SUM(
        CASE
            WHEN PersianCategoryName IS NULL
              OR LTRIM(RTRIM(PersianCategoryName)) = N''
            THEN 1
            ELSE 0
        END
    ) AS MissingPersianNames

FROM meta.ProductCategoryLocalization;
GO


SELECT
    c.SourceCategoryName,
    c.EnglishCategoryName,
    l.PersianCategoryName,
    c.MissingEnglishTranslationFlag

FROM conformed.ProductCategory AS c

LEFT JOIN meta.ProductCategoryLocalization AS l
    ON c.SourceCategoryName = l.SourceCategoryName

ORDER BY c.SourceCategoryName;
GO