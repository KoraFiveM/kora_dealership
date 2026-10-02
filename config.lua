Config = {}

Config.command = 'dealershipcreator'
Config.adminPermission = 'admin'
Config.maxPrice = 5000000

if QB and QB.config and QB.config.adopt then Config = QB.config.adopt(Config) end
