CREATE TABLE IF NOT EXISTS `qbdealerships` (
  `id` VARCHAR(64) NOT NULL,
  `definition` LONGTEXT NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `qbdealership_deleted` (
  `id` VARCHAR(64) NOT NULL,
  `deleted_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `qbdealership_stock` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `dealership` VARCHAR(64) NOT NULL,
  `model` VARCHAR(60) NOT NULL,
  `plate` VARCHAR(15) DEFAULT NULL,
  `source` ENUM('wholesale','trade') NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `qbdealership_stock_plate` (`plate`),
  KEY `qbdealership_stock_lookup` (`dealership`,`model`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `qbdealership_offers` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `dealership` VARCHAR(64) NOT NULL,
  `direction` ENUM('buy','sell') NOT NULL,
  `model` VARCHAR(60) NOT NULL,
  `plate` VARCHAR(15) DEFAULT NULL,
  `citizenid` VARCHAR(50) NOT NULL,
  `customer_name` VARCHAR(128) NOT NULL,
  `amount` INT UNSIGNED DEFAULT NULL,
  `terms` VARCHAR(1000) DEFAULT NULL,
  `counter_amount` INT UNSIGNED DEFAULT NULL,
  `counter_terms` VARCHAR(1000) DEFAULT NULL,
  `status` ENUM('pending','accepted','declined','countered','expired') NOT NULL DEFAULT 'pending',
  `auto_at` TIMESTAMP NULL DEFAULT NULL,
  `expires_at` TIMESTAMP NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `qbdealership_offers_queue` (`status`,`auto_at`),
  KEY `qbdealership_offers_dealer` (`dealership`,`status`),
  KEY `qbdealership_offers_customer` (`citizenid`,`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
