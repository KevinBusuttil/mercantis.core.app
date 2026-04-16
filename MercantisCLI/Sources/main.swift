import ArgumentParser

@main
struct Mercantis: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mercantis",
        abstract: "The Mercantis developer CLI — manage apps, migrations, and patches.",
        version: "0.1.0",
        subcommands: [
            NewApp.self,
            Migrate.self,
            CreatePatch.self,
            RunPatch.self,
            ListApps.self,
            InstallApp.self,
        ]
    )
}
