import gleam/string
import gleeunit/should
import rally/init
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

  let assert Ok(home) = simplifile.read(dir <> "/src/public/pages/home_.gleam")
  home |> string.contains("pub fn server_increment") |> should.be_true()

  let assert Ok(dev) = simplifile.read(dir <> "/bin/dev")
  dev |> string.contains("gleam run -m rally") |> should.be_true()

  cleanup(dir)
}
