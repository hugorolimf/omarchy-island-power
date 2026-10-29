.pragma library

// Texts of this panel: written in Portuguese, English for every other locale.
var english = Qt.locale().name.indexOf("pt") !== 0
var en = {
 "Limite de carga": "Threshold",
 "Na bateria": "On battery",
 "Carga completa": "Fully charged",
 "Carregando": "Charging",
 "Bombeando energia": "Pumping power",
 "Injetando elétrons": "Injecting electrons",
 "Enchendo o tanque": "Pouring juice",
 "Juntando watts": "Amassing watts",
 "Guardando joules": "Hoarding joules",
 "Puxando volts": "Sucking volts",
 "Completando a reserva": "Topping reserves",
 "Absorvendo ampères": "Soaking amps",
 "Inalando quilowatts": "Inhaling kilowatts",
 "Bebericando energia": "Slurping power",
 "Gastando joules": "Spending joules",
 "Drenando watts": "Draining watts",
 "Queimando elétrons": "Burning electrons",
 "Saboreando a carga": "Sipping juice",
 "Gastando coulombs": "Spending coulombs",
 "Sangrando ampères": "Bleeding amps",
 "Devorando volts": "Guzzling volts",
 "Beliscando a reserva": "Munching reserves",
 "Bateria": "Battery",
 "Capacidade": "Battery size",
 "Ciclos de carga": "Charge cycles",
 "Tempo restante": "Time left",
 "Até encher": "Time to full",
 "Estado": "Battery state",
 "Consumo": "Discharging",
 "Carga": "Charging",
 "Mantendo": "Holding",
 "MODO DE ENERGIA": "POWER PROFILE",
 "Economia": "Power saver",
 "Equilibrado": "Balanced",
 "Desempenho": "Performance",
 "Extremo": "Extreme",
 "Poupa bateria e reduz o desempenho": "Saves battery and lowers performance",
 "Equilíbrio entre desempenho e consumo": "Balances performance and power use",
 "Desempenho máximo do sistema": "Full system performance",
 "Limite de potência do firmware (só na tomada)": "Firmware power limit (plugged in only)"
}

function T(s) { return english && en[s] !== undefined ? en[s] : s }
