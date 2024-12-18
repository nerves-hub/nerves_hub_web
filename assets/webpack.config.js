import path from "path"
import glob from "glob"
import { fileURLToPath } from "url"
import MiniCssExtractPlugin from "mini-css-extract-plugin"
import TerserPlugin from "terser-webpack-plugin"
import CssMinimizerPlugin from "css-minimizer-webpack-plugin"
import CopyWebpackPlugin from "copy-webpack-plugin"

const __dirname = path.dirname(fileURLToPath(import.meta.url))

export default (_env, _options) => ({
  cache: true,
  optimization: {
    minimizer: [
      new TerserPlugin({ parallel: true }),
      new CssMinimizerPlugin({})
    ]
  },
  entry: {
    app: glob.sync("./vendor/**/*.js").concat(["./js/app.js"]),
    console: "./js/console.js"
  },
  output: {
    filename: "[name].js",
    path: path.resolve(__dirname, "../priv/static/js")
  },
  module: {
    rules: [
      {
        test: /\.js$/,
        exclude: /node_modules/,
        use: {
          loader: "babel-loader"
        }
      },
      {
        test: /\.s?css$/,
        use: [MiniCssExtractPlugin.loader, "css-loader", "sass-loader"]
      },
      {
        test: /\.(png|jpg|gif|svg)$/,
        loader: "file-loader",
        options: {
          name: "[name].[ext]",
          outputPath: "../images"
        }
      },
      {
        test: /\.(ttf|otf|eot|svg|woff2?)$/,
        loader: "file-loader",
        options: {
          name: "[name].[ext]",
          outputPath: "../fonts"
        }
      }
    ]
  },
  resolve: {
    modules: [
      "node_modules",
      __dirname + "/js",
      __dirname + "/css",
      "~font-awesome/fontawesome-free/scss/fontawesome.scss",
      __dirname + "/images"
    ]
  },
  plugins: [
    new MiniCssExtractPlugin({ filename: "../css/app.css" }),
    new CopyWebpackPlugin({ patterns: [{ from: "static/", to: "../" }] })
  ]
})
