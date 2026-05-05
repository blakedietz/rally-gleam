import argv
import gleam/int
import gleam/io
import gleam/list
import rpc_client as rpc

const base_url = "http://localhost:8080"

pub fn main() {
  case argv.load().arguments {
    ["register", username, email, password] ->
      register(username, email, password)
    ["login", email, password] -> login(email, password)
    ["articles"] -> list_articles()
    ["articles", "--tag", tag] -> list_by_tag(tag)
    ["articles", "--page", page] -> list_page(page)
    _ -> usage()
  }
}

fn register(username: String, email: String, password: String) {
  case rpc.call(base_url:, msg: ServerRegister(username:, email:, password:)) {
    Ok(#(name, _image)) -> io.println("Registered as " <> name)
    Error(rpc.ServerError(msg)) -> io.println_error("Error: " <> msg)
    Error(rpc.HttpError(msg)) -> io.println_error("HTTP error: " <> msg)
  }
}

fn login(email: String, password: String) {
  case rpc.call(base_url:, msg: ServerLogin(email:, password:)) {
    Ok(#(name, _image)) -> io.println("Logged in as " <> name)
    Error(rpc.ServerError(msg)) -> io.println_error("Error: " <> msg)
    Error(rpc.HttpError(msg)) -> io.println_error("HTTP error: " <> msg)
  }
}

fn list_articles() {
  case
    rpc.call(base_url:, msg: ServerSwitchTab(tab_name: "global", tag: ""))
  {
    Ok(#(articles, total)) -> {
      io.println(int.to_string(total) <> " total articles\n")
      print_articles(articles)
    }
    Error(rpc.ServerError(msg)) -> io.println_error("Error: " <> msg)
    Error(rpc.HttpError(msg)) -> io.println_error("HTTP error: " <> msg)
  }
}

fn list_by_tag(tag: String) {
  case rpc.call(base_url:, msg: ServerSwitchTab(tab_name: "tag", tag:)) {
    Ok(#(articles, _total)) -> print_articles(articles)
    Error(rpc.ServerError(msg)) -> io.println_error("Error: " <> msg)
    Error(rpc.HttpError(msg)) -> io.println_error("HTTP error: " <> msg)
  }
}

fn list_page(page_str: String) {
  let page = case int.parse(page_str) {
    Ok(p) -> p
    Error(_) -> 1
  }
  case
    rpc.call(
      base_url:,
      msg: ServerChangePage(page:, tab_name: "global", tag: ""),
    )
  {
    Ok(#(articles, _total)) -> print_articles(articles)
    Error(rpc.ServerError(msg)) -> io.println_error("Error: " <> msg)
    Error(rpc.HttpError(msg)) -> io.println_error("HTTP error: " <> msg)
  }
}

fn print_articles(articles: List(ArticlePreview)) {
  list.each(articles, fn(a) {
    io.println("  " <> a.title)
    io.println("  by " <> a.author_username <> " /" <> a.slug)
    io.println("")
  })
}

fn usage() {
  io.println(
    "realworld-cli: ETF-over-HTTP client for the Lando realworld example

Usage:
  gleam run -- register <username> <email> <password>
  gleam run -- login <email> <password>
  gleam run -- articles
  gleam run -- articles --tag <tag>
  gleam run -- articles --page <n>",
  )
}

// Message types matching the server handlers
pub type ServerLogin {
  ServerLogin(email: String, password: String)
}

pub type ServerRegister {
  ServerRegister(username: String, email: String, password: String)
}

pub type ServerSwitchTab {
  ServerSwitchTab(tab_name: String, tag: String)
}

pub type ServerChangePage {
  ServerChangePage(page: Int, tab_name: String, tag: String)
}

pub type ArticlePreview {
  ArticlePreview(
    slug: String,
    title: String,
    description: String,
    created_at: Int,
    author_username: String,
    author_image: String,
    favorites_count: Int,
  )
}
