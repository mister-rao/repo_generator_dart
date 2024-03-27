/// Dart package to generate repositories using retrofit clients
// ignore_for_file: public_member_api_docs

library repo_generator_dart;

import 'package:build/build.dart';
import 'package:repo_generator_dart/src/generator.dart';
import 'package:source_gen/source_gen.dart';

export 'annotations.dart';

Builder repositoryBuilder(BuilderOptions options) =>
    SharedPartBuilder([RepositoryGenerator()], 'repository');
