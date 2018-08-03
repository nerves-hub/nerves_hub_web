var ExtractTextPlugin = require("extract-text-webpack-plugin");
var CopyWebpackPlugin = require("copy-webpack-plugin");
var merge = require("webpack-merge");
var webpack = require("webpack");

var env = process.env.NODE_ENV || "development";
var production = env === "production";

var node_modules_dir = "node_modules"

var plugins = [
  new ExtractTextPlugin("css/app.css"),
  new webpack.ProvidePlugin({
    $: "jquery",
    jQuery: "jquery"
  }),
  new CopyWebpackPlugin([
      { from: 'images', to: "images" }
  ])
]

if (production) {
  plugins.push(
    new webpack.optimize.UglifyJsPlugin({
      compress: {warnings: false},
      output: {comments: false}
    })
  );
} else {
  plugins.push(
    new webpack.EvalSourceMapDevToolPlugin()
  );
}

var common = {
  module: {
    rules: [
      {
        test: /\.js$/,
        exclude: [],
        loader: "babel-loader",
        options: {
          presets: ["es2015"]
        }
      },
      {
        test: /\.scss$/,
        use: ExtractTextPlugin.extract({
          fallback: 'style-loader',
          use: [
            {
              loader: 'css-loader',
            },
            {
              loader: 'postcss-loader',
              options: {
                plugins() {
                  return [
                    require("precss"),
                    require("autoprefixer")
                  ];
                }
              }
            },
            {
              loader: 'sass-loader'
            }
          ]
        })
      },
      {
        test: /\.(png|jpg|gif|svg)$/,
        loader: "file-loader?name=../priv/static/images/[name].[ext]"
      },
      {
        test: /\.(ttf|otf|eot|svg|woff2?)$/,
        loader: "file-loader?name=/fonts/[name].[ext]",
      }
    ]
  },
  plugins: plugins
};

module.exports = [
  merge(common, {
    entry: [
      __dirname + "/js/app.js",
      __dirname + "/css/app.scss",
    ],
    output: {
      path: __dirname + "/../priv/static",
      filename: "js/app.js"
    },
    resolve: {
      modules: [
        node_modules_dir,
        __dirname + "/js",
        __dirname + "/css",
        __dirname + "/images"
      ]
    }
  })
];