//
//  AppDefaults.swift
//  PromptGrid
//
//  The app-level default generation configuration, copied into each new project
//  (which in turn copies it into each new prompt). Device-local (UserDefaults),
//  stored as the same JSON the config editor shows.
//

import Foundation
import PromptGridCore

enum AppDefaults {
    private static let generationConfigKey = "defaultGenerationConfig"

    static func generationConfig() -> DrawThingsConfigurationDTO {
        guard let data = UserDefaults.standard.data(forKey: generationConfigKey),
              let dto = try? ProjectPackage.makeDecoder()
                .decode(DrawThingsConfigurationDTO.self, from: data)
        else { return DrawThingsConfigurationDTO() }
        return dto
    }

    static func setGenerationConfig(_ dto: DrawThingsConfigurationDTO) {
        if let data = try? ProjectPackage.makeEncoder().encode(dto) {
            UserDefaults.standard.set(data, forKey: generationConfigKey)
        }
    }
}
