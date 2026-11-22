-- Module Script
local Names = {

	["British"] = {
		FirstNames = {
			"James", "Oliver", "Thomas", "William", "Arthur",
			"George", "Edward", "Henry", "Charles", "Jack",
			"Daniel", "Samuel", "Benjamin", "Harry", "Louis",
		},

		LastNames = {
			"Blackwood", "Crawford", "Sinclair", "Whitmore", "Harrington",
			"Fletcher", "Sterling", "Carter", "Bennett", "Hawthorne",
			"Prescott", "Wellington", "Graves", "Mercer", "Ashford",
		},
	},

	["French"] = {
		FirstNames = {
			"Antoine", "Julien", "Gabriel", "Louis", "Étienne",
			"Laurent", "Marc", "Nicolas", "Pierre", "François",
			"Henri", "Victor", "Adrien", "Mathieu", "Luc",
		},

		LastNames = {
			"Moreau", "Laurent", "Dubois", "Leroux", "Fontaine",
			"Mercier", "Renaud", "Beaumont", "Chevalier", "Marchand",
			"De La Croix", "Dufour", "Renard", "Garnier", "Rousseau",
		},
	},

	["East Asian"] = {
		FirstNames = {
			"Haruto", "Ren", "Sota", "Yuki", "Kaito",
			"Takumi", "Riku", "Daiki", "Shota", "Kenji",
			"Akira", "Hiroshi", "Naoki", "Shinsuke", "Takeshi",
			"Wei", "Jun", "Hao", "Ming", "Chen",
			"Lei", "Kai", "Jian", "Feng", "Bo",
			"Ji-ho", "Seo-jun", "Min-jun", "Hyun-woo", "Do-yun",
		},

		LastNames = {
			"Sato", "Suzuki", "Takahashi", "Tanaka", "Watanabe",
			"Ito", "Yamamoto", "Nakamura", "Kobayashi", "Kato",
			"Yoshida", "Yamada", "Sasaki", "Matsumoto", "Fujimoto",
			"Wang", "Li", "Zhang", "Liu", "Chen",
			"Yang", "Huang", "Wu", "Zhou", "Xu",
			"Kim", "Lee", "Park", "Choi", "Jung",
		},
	},

	["American"] = {
		FirstNames = {
			"Michael", "James", "Robert", "John", "William",
			"David", "Christopher", "Matthew", "Andrew", "Ryan",
			"Daniel", "Jason", "Jonathan", "Nathan", "Ethan",
		},

		LastNames = {
			"Mitchell", "Anderson", "Morgan", "Walker", "Hayes",
			"Reed", "Parker", "Collins", "Bennett", "Carter",
			"Brooks", "Harrison", "Cooper", "Miller", "Grant",
		},
	},

	["Spanish"] = {
		FirstNames = {
			"Carlos", "Miguel", "Alejandro", "Javier", "Diego",
			"Mateo", "Luis", "Fernando", "Rafael", "Santiago",
			"Adrian", "Pablo", "Sergio", "Jorge", "Antonio",
		},

		LastNames = {
			"Navarro", "Garcia", "Moreno", "Castillo", "Vega",
			"Torres", "Serrano", "Mendoza", "Ortega", "Delgado",
			"Romero", "Fuentes", "Marquez", "Cabrera", "Santos",
		},
	},

	["Italian"] = {
		FirstNames = {
			"Marco", "Luca", "Matteo", "Alessandro", "Lorenzo",
			"Giovanni", "Andrea", "Francesco", "Davide", "Stefano",
			"Antonio", "Riccardo", "Fabio", "Enzo", "Paolo",
		},

		LastNames = {
			"Moretti", "Romano", "Ferrari", "Rossi", "Conti",
			"Marino", "Ricci", "Lombardi", "De Luca", "Bianchi",
			"Esposito", "Gallo", "Vitale", "Rinaldi", "Costa",
		},
	},

	["German"] = {
		FirstNames = {
			"Felix", "Maximilian", "Alexander", "Leon", "Lukas",
			"Jonas", "Paul", "Niklas", "Florian", "Sebastian",
			"Daniel", "Martin", "Thomas", "Markus", "Stefan",
		},

		LastNames = {
			"Schmidt", "Müller", "Schneider", "Fischer", "Weber",
			"Wagner", "Becker", "Hoffmann", "Keller", "Richter",
			"Wolf", "Krüger", "Hartmann", "Vogel", "Krause",
		},
	},

	["Eastern European"] = {
		FirstNames = {
			"Alexei", "Dmitri", "Ivan", "Mikhail", "Nikolai",
			"Sergei", "Viktor", "Andrei", "Yuri", "Roman",
			"Artem", "Maxim", "Vladimir", "Oleg", "Pavel",
			"Jakub", "Mateusz", "Szymon", "Marek", "Piotr",
			"Tomas", "Petr", "Ondrej", "Lukas", "David",
			"Laszlo", "Zoltan", "Gabor", "Tamas", "Andras",
		},

		LastNames = {
			"Volkov", "Petrov", "Sokolov", "Morozov", "Orlov",
			"Lebedev", "Kozlov", "Novikov", "Kuznetsov", "Fedorov",
			"Antonov", "Romanov", "Makarov", "Baranov", "Zaitsev",
			"Kowalski", "Nowak", "Wisniewski", "Zielinski", "Kaminski",
			"Novak", "Svoboda", "Dvorak", "Kucera", "Vesely",
			"Nagy", "Kovacs", "Toth", "Szabo", "Horvath",
		},
	},

	["Arabic"] = {
		FirstNames = {
			"Omar", "Youssef", "Khalid", "Karim", "Hassan",
			"Samir", "Tariq", "Amir", "Nabil", "Faris",
			"Rami", "Zayd", "Mansour", "Adil", "Sami",
		},

		LastNames = {
			"Al-Saadi", "Al-Hassan", "Al-Mansouri", "Al-Rashid",
			"Al-Fahad", "Al-Karim", "Al-Najjar", "Al-Hakim",
			"Al-Masri", "Al-Farsi", "Al-Qasim", "Al-Hadi",
		},
	},

	["African"] = {
		FirstNames = {
			"Jean", "David", "Emmanuel", "Patrick", "Samuel",
			"Christian", "Daniel", "Joseph", "Michel", "Gabriel",
			"Marc", "Alexandre", "Victor", "Paul", "Simon","Koffi",
			"Ade","Ayo","Kwame","Omari", "Musa", "Deji", "Kweku",
			"Abiola"
		},

		LastNames = {
			"Okoro", "Mwamba", "Kabeya", "Kalume", "Mabiala",
			"Ilunga", "Kabila", "Bemba", "Mbuyi", "Tshisekedi",
			"Bakari", "N'Diaye", "Okafor", "Mensah", "Diallo",
			"Olomide","Ipupa","Kabore","Koulibaily","Asare", "Ekong",
			"Osakwe", "Baako", "Amissi", "Makanda", "Filaniu"
		},
	},

	["South American"] = {
		FirstNames = {
			"Mateo", "Santiago", "Lucas", "Gabriel", "Rafael",
			"Emilio", "Nicolas", "Sebastian", "Alejandro", "Felipe",
			"Gustavo", "Rodrigo", "Thiago", "Diego", "Andres",
		},

		LastNames = {
			"Silva", "Souza", "Costa", "Almeida", "Ferreira",
			"Gonzalez", "Rodriguez", "Fernandez", "Lopez", "Martinez",
			"Perez", "Castillo", "Rojas", "Vargas", "Mendoza",
		},
	},

	["South Asian"] = {
		FirstNames = {
			"Arjun", "Rohan", "Vikram", "Raj", "Amit",
			"Sanjay", "Rahul", "Karan", "Aditya", "Nikhil",
			"Imran", "Farhan", "Salman", "Aman", "Vivek",
		},

		LastNames = {
			"Sharma", "Patel", "Singh", "Kumar", "Gupta",
			"Mehta", "Khan", "Malhotra", "Chaudhry", "Iqbal",
			"Rahman", "Ahmed", "Kapoor", "Verma", "Reddy",
		},
	},
}

return Names
