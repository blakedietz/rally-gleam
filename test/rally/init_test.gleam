import gleam/string
import gleeunit/should
import rally/internal/init
import simplifile

fn make_temp_dir(name: String) -> String {
  let path = "/tmp/rally_init_test_" <> name
  let _ = simplifile.delete(file_or_dir_at: path)
  let assert Ok(Nil) = simplifile.create_directory_all(path)
  path
}

fn cleanup(path: String) -> Nil {
  let _ = simplifile.delete(file_or_dir_at: path)
  Nil
}

pub fn init_project_writes_hex_scaffold_test() {
  let dir = make_temp_dir("hex_scaffold")
  let assert Ok(Nil) = init.init_project(dir)

  let assert Ok(toml) = simplifile.read(dir <> "/gleam.toml")
  toml
  |> string.contains("name = \"rally_init_test_hex_scaffold\"")
  |> should.be_true()
  toml
  |> string.contains("rally = \">= 1.0.0 and < 2.0.0\"")
  |> should.be_true()
  toml
  |> string.contains("libero = \">= 6.0.0 and < 7.0.0\"")
  |> should.be_true()

  let assert Ok(env) = simplifile.read(dir <> "/.env")
  let assert Ok(env_example) = simplifile.read(dir <> "/.env.example")
  env |> should.equal(env_example)
  env |> string.contains("APP_ENV=dev") |> should.be_true()
  env |> string.contains("LOG_LEVEL=debug") |> should.be_true()
  env |> string.contains("PORT=8080") |> should.be_true()

  let assert Ok(gitignore) = simplifile.read(dir <> "/.gitignore")
  gitignore |> string.contains(".env") |> should.be_true()

  let assert Ok(home) = simplifile.read(dir <> "/src/public/pages/home_.gleam")
  home |> string.contains("pub fn server_increment") |> should.be_true()

  let assert Ok(dev) = simplifile.read(dir <> "/bin/dev")
  dev |> string.contains("gleam run -m rally") |> should.be_true()
  dev |> string.contains("PORT_OVERRIDE=\"${PORT:-}\"") |> should.be_true()
  dev |> string.contains("export PORT=\"${PORT:-8080}\"") |> should.be_true()
  dev |> string.contains("http://localhost:${PORT}") |> should.be_true()

  let assert Ok(app) =
    simplifile.read(dir <> "/src/rally_init_test_hex_scaffold.gleam")
  app |> string.contains("envoy.get(\"PORT\")") |> should.be_true()
  app |> string.contains("|> mist.port(port)") |> should.be_true()
  app
  |> string.contains("case string.starts_with(path, \"/_build/\")")
  |> should.be_true()

  simplifile.read(dir <> "/src/app.gleam")
  |> should.be_error()

  let assert Ok(shell) = simplifile.read(dir <> "/src/public/shell.html")
  shell
  |> string.contains(
    "import { main } from \"/_build/client/generated/app.mjs\"",
  )
  |> should.be_true()
  shell
  |> string.contains("main();")
  |> should.be_true()

  cleanup(dir)
}

pub fn init_project_replaces_default_gleam_new_files_test() {
  let dir = make_temp_dir("default_gleam_new")
  let assert Ok(Nil) = simplifile.create_directory_all(dir <> "/src")
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/src/rally_init_test_default_gleam_new.gleam",
      "import gleam/io

pub fn main() -> Nil {
  io.println(\"Hello from rally_init_test_default_gleam_new!\")
}
",
    )
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/gleam.toml",
      "name = \"rally_init_test_default_gleam_new\"
version = \"1.0.0\"

# Fill out these fields if you intend to generate HTML documentation or publish
# your project to the Hex package manager.
#
# description = \"\"
# licences = [\"Apache-2.0\"]
# repository = { type = \"github\", user = \"\", repo = \"\" }
# links = [{ title = \"Website\", href = \"\" }]
#
# For a full reference of all the available options, you can have a look at
# https://gleam.run/writing-gleam/gleam-toml/.

[dependencies]
gleam_stdlib = \">= 1.0.0 and < 2.0.0\"
rally = { path = \"/tmp/rally\" }

[dev_dependencies]
gleeunit = \">= 1.0.0 and < 2.0.0\"
",
    )
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/.gitignore",
      "*.beam
*.ez
/build
erl_crash.dump
",
    )

  let assert Ok(Nil) = init.init_project(dir)
  let assert Ok(app) =
    simplifile.read(dir <> "/src/rally_init_test_default_gleam_new.gleam")
  app |> string.contains("Hello from") |> should.equal(False)
  app |> string.contains("pub fn main()") |> should.be_true()

  cleanup(dir)
}

pub fn init_project_refuses_to_overwrite_user_module_test() {
  let dir = make_temp_dir("user_module")
  let assert Ok(Nil) = simplifile.create_directory_all(dir <> "/src")
  let assert Ok(Nil) =
    simplifile.write(
      dir <> "/src/rally_init_test_user_module.gleam",
      "pub fn main() -> Nil {
  Nil
}
",
    )

  case init.init_project(dir) {
    Ok(_) -> should.fail()
    Error(message) -> {
      message
      |> string.contains(
        "Refusing to overwrite src/rally_init_test_user_module.gleam",
      )
      |> should.be_true()
      message |> string.contains("It may contain your code") |> should.be_true()
      message
      |> string.contains("fresh `gleam new` project")
      |> should.be_true()
    }
  }

  simplifile.read(dir <> "/.env")
  |> should.be_error()

  cleanup(dir)
}

pub fn init_project_refuses_empty_existing_scaffold_file_test() {
  let dir = make_temp_dir("empty_file")
  let assert Ok(Nil) = simplifile.write(dir <> "/.env", "")

  case init.init_project(dir) {
    Ok(_) -> should.fail()
    Error(message) -> {
      message
      |> string.contains("Refusing to overwrite .env")
      |> should.be_true()
    }
  }

  cleanup(dir)
}

pub fn init_project_refuses_existing_scaffold_directory_test() {
  let dir = make_temp_dir("directory_collision")
  let assert Ok(Nil) = simplifile.create_directory(dir <> "/.env")

  case init.init_project(dir) {
    Ok(_) -> should.fail()
    Error(message) -> {
      message
      |> string.contains("Refusing to overwrite .env")
      |> should.be_true()
      message
      |> string.contains("already exists as a directory")
      |> should.be_true()
    }
  }

  simplifile.read(dir <> "/bin/dev")
  |> should.be_error()

  cleanup(dir)
}
