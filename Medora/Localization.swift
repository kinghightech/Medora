//
//  Localization.swift
//  Medora
//
//  A lightweight, offline, in-app translation system. Users pick a language
//  in the Profile tab and the whole post-onboarding UI re-renders instantly —
//  no network, no API keys. English strings are used as the lookup keys, so
//  call sites stay readable: `loc.t("Today's Health")`.
//
//  Views that show translatable text observe the shared manager:
//      @ObservedObject private var loc = LocalizationManager.shared
//  and a language change republishes, re-rendering them.
//

import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case chinese = "zh"
    case hindi = "hi"

    var id: String { rawValue }

    /// Name shown in its own language.
    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .french:  return "Français"
        case .german:  return "Deutsch"
        case .chinese: return "中文"
        case .hindi:   return "हिन्दी"
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .spanish: return "🇪🇸"
        case .french:  return "🇫🇷"
        case .german:  return "🇩🇪"
        case .chinese: return "🇨🇳"
        case .hindi:   return "🇮🇳"
        }
    }

    /// BCP-47 language used by Apple's on-device Translation framework.
    var localeLanguage: Locale.Language {
        switch self {
        case .english: return Locale.Language(identifier: "en")
        case .spanish: return Locale.Language(identifier: "es")
        case .french:  return Locale.Language(identifier: "fr")
        case .german:  return Locale.Language(identifier: "de")
        case .chinese: return Locale.Language(identifier: "zh-Hans")
        case .hindi:   return Locale.Language(identifier: "hi")
        }
    }
}

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published private(set) var language: AppLanguage

    private let storageKey = "medora.language"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let lang = AppLanguage(rawValue: raw) {
            language = lang
        } else {
            language = .english
        }
    }

    func setLanguage(_ lang: AppLanguage) {
        guard lang != language else { return }
        language = lang
        UserDefaults.standard.set(lang.rawValue, forKey: storageKey)
    }

    /// Translate an English source string into the selected language.
    /// Falls back to the original string when no translation exists.
    func t(_ key: String) -> String {
        guard language != .english else { return key }
        return Self.translations[language]?[key] ?? key
    }

    // MARK: - Translation tables (English source string -> localized string)

    private static let translations: [AppLanguage: [String: String]] = [
        .spanish: [
            "Home": "Inicio",
            "Checklist": "Lista",
            "AI": "IA",
            "Trials": "Ensayos",
            "Profile": "Perfil",
            "Welcome": "Bienvenido",
            "Welcome back": "Bienvenido de nuevo",
            "Today's Health": "Salud de hoy",
            "Calories burned": "Calorías quemadas",
            "Steps": "Pasos",
            "Sleep data": "Datos de sueño",
            "Today's Tasks": "Tareas de hoy",
            "No tasks for today yet.": "Aún no hay tareas para hoy.",
            "Add tasks in the Checklist tab and they'll appear here.": "Agrega tareas en la pestaña Lista y aparecerán aquí.",
            "No data available": "No hay datos disponibles",
            "Today": "Hoy",
            "No tasks yet, add one below.": "Aún no hay tareas: agrega una abajo.",
            "All done for this day. 🎉": "Todo listo por hoy. 🎉",
            "complete": "completado",
            "Tasks": "Tareas",
            "Add a task for this day": "Agregar una tarea para este día",
            "No tasks for this day yet.": "Aún no hay tareas para este día.",
            "Clinical Trials": "Ensayos clínicos",
            "Find trials near you": "Encuentra ensayos cerca de ti",
            "City, state, or ZIP code": "Ciudad, estado o código postal",
            "Searching…": "Buscando…",
            "Search": "Buscar",
            "Something went wrong": "Algo salió mal",
            "Looking for trials…": "Buscando ensayos…",
            "No upcoming trials found": "No se encontraron ensayos próximos",
            "Try a nearby city or widen your search.": "Prueba con una ciudad cercana o amplía tu búsqueda.",
            "Search for nearby trials": "Busca ensayos cercanos",
            "Enter your location to see upcoming and recruiting clinical trials from ClinicalTrials.gov.": "Ingresa tu ubicación para ver ensayos clínicos próximos y en reclutamiento de ClinicalTrials.gov.",
            "View on ClinicalTrials.gov": "Ver en ClinicalTrials.gov",
            "Language": "Idioma",
            "Choose your language": "Elige tu idioma",
            "App Language": "Idioma de la app",
            "Settings": "Ajustes",
            "The whole app updates instantly.": "Toda la app se actualiza al instante.",
        ],
        .french: [
            "Home": "Accueil",
            "Checklist": "Liste",
            "AI": "IA",
            "Trials": "Essais",
            "Profile": "Profil",
            "Welcome": "Bienvenue",
            "Welcome back": "Bon retour",
            "Today's Health": "Santé du jour",
            "Calories burned": "Calories brûlées",
            "Steps": "Pas",
            "Sleep data": "Données de sommeil",
            "Today's Tasks": "Tâches du jour",
            "No tasks for today yet.": "Aucune tâche pour aujourd'hui.",
            "Add tasks in the Checklist tab and they'll appear here.": "Ajoutez des tâches dans l'onglet Liste et elles apparaîtront ici.",
            "No data available": "Aucune donnée disponible",
            "Today": "Aujourd'hui",
            "No tasks yet, add one below.": "Aucune tâche — ajoutez-en une ci-dessous.",
            "All done for this day. 🎉": "Tout est fait pour aujourd'hui. 🎉",
            "complete": "terminé",
            "Tasks": "Tâches",
            "Add a task for this day": "Ajouter une tâche pour ce jour",
            "No tasks for this day yet.": "Aucune tâche pour ce jour.",
            "Clinical Trials": "Essais cliniques",
            "Find trials near you": "Trouvez des essais près de chez vous",
            "City, state, or ZIP code": "Ville, état ou code postal",
            "Searching…": "Recherche…",
            "Search": "Rechercher",
            "Something went wrong": "Une erreur s'est produite",
            "Looking for trials…": "Recherche d'essais…",
            "No upcoming trials found": "Aucun essai à venir trouvé",
            "Try a nearby city or widen your search.": "Essayez une ville proche ou élargissez votre recherche.",
            "Search for nearby trials": "Rechercher des essais à proximité",
            "Enter your location to see upcoming and recruiting clinical trials from ClinicalTrials.gov.": "Saisissez votre position pour voir les essais cliniques à venir et en recrutement de ClinicalTrials.gov.",
            "View on ClinicalTrials.gov": "Voir sur ClinicalTrials.gov",
            "Language": "Langue",
            "Choose your language": "Choisissez votre langue",
            "App Language": "Langue de l'app",
            "Settings": "Réglages",
            "The whole app updates instantly.": "Toute l'application se met à jour instantanément.",
        ],
        .german: [
            "Home": "Start",
            "Checklist": "Checkliste",
            "AI": "KI",
            "Trials": "Studien",
            "Profile": "Profil",
            "Welcome": "Willkommen",
            "Welcome back": "Willkommen zurück",
            "Today's Health": "Heutige Gesundheit",
            "Calories burned": "Verbrannte Kalorien",
            "Steps": "Schritte",
            "Sleep data": "Schlafdaten",
            "Today's Tasks": "Heutige Aufgaben",
            "No tasks for today yet.": "Noch keine Aufgaben für heute.",
            "Add tasks in the Checklist tab and they'll appear here.": "Füge Aufgaben im Checklisten-Tab hinzu, sie erscheinen hier.",
            "No data available": "Keine Daten verfügbar",
            "Today": "Heute",
            "No tasks yet, add one below.": "Noch keine Aufgaben – füge unten eine hinzu.",
            "All done for this day. 🎉": "Alles für heute erledigt. 🎉",
            "complete": "abgeschlossen",
            "Tasks": "Aufgaben",
            "Add a task for this day": "Aufgabe für diesen Tag hinzufügen",
            "No tasks for this day yet.": "Noch keine Aufgaben für diesen Tag.",
            "Clinical Trials": "Klinische Studien",
            "Find trials near you": "Studien in deiner Nähe finden",
            "City, state, or ZIP code": "Stadt, Bundesland oder PLZ",
            "Searching…": "Suche…",
            "Search": "Suchen",
            "Something went wrong": "Etwas ist schiefgelaufen",
            "Looking for trials…": "Suche nach Studien…",
            "No upcoming trials found": "Keine bevorstehenden Studien gefunden",
            "Try a nearby city or widen your search.": "Versuche eine nahegelegene Stadt oder erweitere deine Suche.",
            "Search for nearby trials": "Studien in der Nähe suchen",
            "Enter your location to see upcoming and recruiting clinical trials from ClinicalTrials.gov.": "Gib deinen Standort ein, um bevorstehende und rekrutierende klinische Studien von ClinicalTrials.gov zu sehen.",
            "View on ClinicalTrials.gov": "Auf ClinicalTrials.gov ansehen",
            "Language": "Sprache",
            "Choose your language": "Wähle deine Sprache",
            "App Language": "App-Sprache",
            "Settings": "Einstellungen",
            "The whole app updates instantly.": "Die gesamte App wird sofort aktualisiert.",
        ],
        .chinese: [
            "Home": "主页",
            "Checklist": "清单",
            "AI": "AI",
            "Trials": "试验",
            "Profile": "个人",
            "Welcome": "欢迎",
            "Welcome back": "欢迎回来",
            "Today's Health": "今日健康",
            "Calories burned": "消耗的卡路里",
            "Steps": "步数",
            "Sleep data": "睡眠数据",
            "Today's Tasks": "今日任务",
            "No tasks for today yet.": "今天还没有任务。",
            "Add tasks in the Checklist tab and they'll appear here.": "在清单标签中添加任务，它们会显示在这里。",
            "No data available": "暂无数据",
            "Today": "今天",
            "No tasks yet, add one below.": "还没有任务——在下方添加一个。",
            "All done for this day. 🎉": "今天全部完成。🎉",
            "complete": "完成",
            "Tasks": "任务",
            "Add a task for this day": "为这一天添加任务",
            "No tasks for this day yet.": "这一天还没有任务。",
            "Clinical Trials": "临床试验",
            "Find trials near you": "查找您附近的试验",
            "City, state, or ZIP code": "城市、州或邮政编码",
            "Searching…": "搜索中…",
            "Search": "搜索",
            "Something went wrong": "出错了",
            "Looking for trials…": "正在查找试验…",
            "No upcoming trials found": "未找到即将开始的试验",
            "Try a nearby city or widen your search.": "尝试附近的城市或扩大搜索范围。",
            "Search for nearby trials": "搜索附近的试验",
            "Enter your location to see upcoming and recruiting clinical trials from ClinicalTrials.gov.": "输入您的位置，查看来自 ClinicalTrials.gov 的即将开始和正在招募的临床试验。",
            "View on ClinicalTrials.gov": "在 ClinicalTrials.gov 上查看",
            "Language": "语言",
            "Choose your language": "选择您的语言",
            "App Language": "应用语言",
            "Settings": "设置",
            "The whole app updates instantly.": "整个应用会立即更新。",
        ],
        .hindi: [
            "Home": "होम",
            "Checklist": "चेकलिस्ट",
            "AI": "एआई",
            "Trials": "परीक्षण",
            "Profile": "प्रोफ़ाइल",
            "Welcome": "स्वागत है",
            "Welcome back": "वापसी पर स्वागत है",
            "Today's Health": "आज का स्वास्थ्य",
            "Calories burned": "जली हुई कैलोरी",
            "Steps": "कदम",
            "Sleep data": "नींद का डेटा",
            "Today's Tasks": "आज के कार्य",
            "No tasks for today yet.": "आज के लिए अभी कोई कार्य नहीं।",
            "Add tasks in the Checklist tab and they'll appear here.": "चेकलिस्ट टैब में कार्य जोड़ें और वे यहाँ दिखाई देंगे।",
            "No data available": "कोई डेटा उपलब्ध नहीं",
            "Today": "आज",
            "No tasks yet, add one below.": "अभी कोई कार्य नहीं — नीचे एक जोड़ें।",
            "All done for this day. 🎉": "आज के लिए सब पूरा। 🎉",
            "complete": "पूर्ण",
            "Tasks": "कार्य",
            "Add a task for this day": "इस दिन के लिए कार्य जोड़ें",
            "No tasks for this day yet.": "इस दिन के लिए अभी कोई कार्य नहीं।",
            "Clinical Trials": "नैदानिक परीक्षण",
            "Find trials near you": "अपने पास परीक्षण खोजें",
            "City, state, or ZIP code": "शहर, राज्य या ज़िप कोड",
            "Searching…": "खोज रहे हैं…",
            "Search": "खोजें",
            "Something went wrong": "कुछ गलत हो गया",
            "Looking for trials…": "परीक्षण खोजे जा रहे हैं…",
            "No upcoming trials found": "कोई आगामी परीक्षण नहीं मिला",
            "Try a nearby city or widen your search.": "किसी नज़दीकी शहर को आज़माएँ या अपनी खोज बढ़ाएँ।",
            "Search for nearby trials": "पास के परीक्षण खोजें",
            "Enter your location to see upcoming and recruiting clinical trials from ClinicalTrials.gov.": "ClinicalTrials.gov से आगामी और भर्ती कर रहे नैदानिक परीक्षण देखने के लिए अपना स्थान दर्ज करें।",
            "View on ClinicalTrials.gov": "ClinicalTrials.gov पर देखें",
            "Language": "भाषा",
            "Choose your language": "अपनी भाषा चुनें",
            "App Language": "ऐप की भाषा",
            "Settings": "सेटिंग्स",
            "The whole app updates instantly.": "पूरा ऐप तुरंत अपडेट हो जाता है।",
        ],
    ]
}
