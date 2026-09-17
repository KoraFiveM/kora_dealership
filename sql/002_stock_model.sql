ALTER TABLE `qbdealership_stock`
  ADD COLUMN IF NOT EXISTS `model` VARCHAR(60) NOT NULL AFTER `dealership`;

ALTER TABLE `qbdealership_stock`
  ADD KEY IF NOT EXISTS `qbdealership_stock_lookup` (`dealership`,`model`);
