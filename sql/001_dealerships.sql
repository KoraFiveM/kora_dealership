CREATE TABLE IF NOT EXISTS `qbdealerships` (
  `id` VARCHAR(64) NOT NULL,
  `label` VARCHAR(128) NOT NULL DEFAULT '',
  `type` ENUM('public','for_sale','owned') NOT NULL DEFAULT 'public',
  `price` INT UNSIGNED DEFAULT NULL,
  `owner` VARCHAR(50) DEFAULT NULL,
  `zone` LONGTEXT DEFAULT NULL,
  `vehicles` LONGTEXT DEFAULT NULL,
  `placements` LONGTEXT DEFAULT NULL,
  `spawns` LONGTEXT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `qbdealership_offers` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `dealership_id` varchar(64) NOT NULL,
  `model` varchar(64) NOT NULL,
  `offer_price` int(10) unsigned NOT NULL,
  `offer_text` varchar(500) NOT NULL DEFAULT '',
  `auto_accept_at` datetime DEFAULT NULL,
  `status` enum('pending','accepted','denied') NOT NULL DEFAULT 'pending',
  `offeror` varchar(50) NOT NULL,
  `acceptor` varchar(50) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_offers_dealership` (`dealership_id`),
  KEY `idx_offers_offeror` (`offeror`),
  KEY `idx_offers_pending_auto_accept` (`status`, `auto_accept_at`),
  CONSTRAINT `fk_offers_dealership`
    FOREIGN KEY (`dealership_id`) REFERENCES `qbdealerships` (`id`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
