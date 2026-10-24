-- ============================================================
-- Bioprocess lab database: MySQL 8.0+ schema, data and queries
-- Run:  mysql -u lab_admin -p bioprocess < bioprocess_mysql.sql
-- (CHECK constraints need MySQL 8.0.16+, window functions 8.0+)
-- ============================================================

-- 1. Tables ---------------------------------------------------
CREATE TABLE strain (
    strain_id     INT AUTO_INCREMENT PRIMARY KEY,
    name          VARCHAR(100) NOT NULL UNIQUE,
    organism      VARCHAR(100) NOT NULL,
    genotype      TEXT
) ENGINE=InnoDB;

CREATE TABLE run (
    run_id        INT AUTO_INCREMENT PRIMARY KEY,
    strain_id     INT NOT NULL,
    reactor       VARCHAR(50) NOT NULL,
    mode          VARCHAR(20) NOT NULL
                  CHECK (mode IN ('batch', 'fed-batch', 'continuous')),
    temperature_c DECIMAL(4,1) CHECK (temperature_c BETWEEN 0 AND 100),
    ph_setpoint   DECIMAL(3,1) CHECK (ph_setpoint BETWEEN 0 AND 14),
    started_at    DATETIME NOT NULL,
    operator      VARCHAR(50),
    FOREIGN KEY (strain_id) REFERENCES strain(strain_id)
) ENGINE=InnoDB;

CREATE TABLE sample (
    sample_id     INT AUTO_INCREMENT PRIMARY KEY,
    run_id        INT NOT NULL,
    time_h        DECIMAL(6,2) NOT NULL CHECK (time_h >= 0),
    od600         DECIMAL(6,3) CHECK (od600 >= 0),
    biomass_g_l   DECIMAL(6,3) CHECK (biomass_g_l >= 0),
    glucose_g_l   DECIMAL(6,3) CHECK (glucose_g_l >= 0),
    product_g_l   DECIMAL(6,3) CHECK (product_g_l >= 0),
    UNIQUE (run_id, time_h),
    FOREIGN KEY (run_id) REFERENCES run(run_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_sample_run_time ON sample (run_id, time_h);

-- 2. Data ----------------------------------------------------
INSERT INTO strain (name, organism, genotype) VALUES
  ('EC-WT',   'Escherichia coli', 'K-12 MG1655 wild type'),
  ('EC-SUC1', 'Escherichia coli', 'MG1655 delta-ldhA delta-pflB');

INSERT INTO run (strain_id, reactor, mode, temperature_c, ph_setpoint, started_at, operator) VALUES
  (1, 'BR-01', 'batch',     37.0, 7.0, '2026-10-01 09:00:00', 'A. Oyeodibo'),
  (2, 'BR-02', 'fed-batch', 37.0, 6.8, '2026-10-01 09:30:00', 'A. Oyeodibo');

INSERT INTO sample (run_id, time_h, od600, biomass_g_l, glucose_g_l, product_g_l) VALUES
  (1, 0, 0.10, 0.04, 20.0, 0.0),
  (1, 2, 0.35, 0.14, 19.1, 0.1),
  (1, 4, 1.20, 0.48, 16.0, 0.4),
  (1, 6, 3.80, 1.52,  9.8, 1.0),
  (1, 8, 6.10, 2.44,  2.1, 1.6),
  (2, 0, 0.10, 0.04, 20.0, 0.0),
  (2, 4, 1.05, 0.42, 16.5, 0.9),
  (2, 8, 4.90, 1.96,  6.0, 3.8),
  (2, 12, 8.20, 3.28, 4.5, 7.2),
  (2, 16, 10.4, 4.16, 3.9, 10.5);

-- 3. Queries -------------------------------------------------
-- 3a. All samples with strain and run details (JOIN)
SELECT r.run_id, s.name AS strain, r.mode, sa.time_h, sa.biomass_g_l, sa.product_g_l
FROM sample sa
JOIN run r    ON r.run_id = sa.run_id
JOIN strain s ON s.strain_id = r.strain_id
ORDER BY r.run_id, sa.time_h;

-- 3b. Final titer, glucose used and product yield per run (aggregates)
SELECT r.run_id, s.name AS strain,
       MAX(sa.product_g_l)                                        AS final_titer_g_l,
       MAX(sa.glucose_g_l) - MIN(sa.glucose_g_l)                  AS glucose_used_g_l,
       ROUND(MAX(sa.product_g_l) /
             NULLIF(MAX(sa.glucose_g_l) - MIN(sa.glucose_g_l), 0), 3) AS yield_g_per_g
FROM sample sa
JOIN run r    ON r.run_id = sa.run_id
JOIN strain s ON s.strain_id = r.strain_id
GROUP BY r.run_id, s.name
ORDER BY r.run_id;

-- 3c. Specific growth rate between samples (window function)
SELECT run_id, time_h, biomass_g_l,
       ROUND(LN(biomass_g_l / LAG(biomass_g_l) OVER w)
             / (time_h - LAG(time_h) OVER w), 3) AS mu_per_h
FROM sample
WINDOW w AS (PARTITION BY run_id ORDER BY time_h)
ORDER BY run_id, time_h;

-- 3d. A reusable view of run summaries
CREATE VIEW run_summary AS
SELECT r.run_id, s.name AS strain, r.mode, r.reactor,
       MAX(sa.time_h)      AS duration_h,
       MAX(sa.biomass_g_l) AS max_biomass_g_l,
       MAX(sa.product_g_l) AS final_titer_g_l
FROM run r
JOIN strain s      ON s.strain_id = r.strain_id
LEFT JOIN sample sa ON sa.run_id = r.run_id
GROUP BY r.run_id, s.name, r.mode, r.reactor;

SELECT * FROM run_summary ORDER BY run_id;
