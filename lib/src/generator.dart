// ignore_for_file: public_member_api_docs

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'package:source_gen/source_gen.dart';

import '../repo_generator.dart';

class RepositoryGenerator extends GeneratorForAnnotation<RepositoryClass> {
  static const _clientVar = '_client';

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      final name = element.displayName;
      throw InvalidGenerationSourceError(
        'Generator cannot target `$name`.',
        todo: 'Remove the [RepositoryClass] annotation from `$name`.',
      );
    }

    return _implementClass(element, annotation);
  }

  String _implementClass(ClassElement element, ConstantReader annotation) {
    final className = element.name;

    final retrofitClient =
        element.constructors[0].parameters[0].type.element!.name;

    final annotClassConsts = element.constructors
        .where((c) => !c.isFactory && !c.isDefaultConstructor);

    final classBuilder = Class((c) {
      c
        ..name = '_$className'
        ..types.addAll(element.typeParameters.map((e) => refer(e.name)))
        ..fields.addAll([_buildClientFiled(retrofitClient!)])
        ..constructors.addAll(
          annotClassConsts.map(
            (e) => _generateConstructor(superClassConst: e),
          ),
        )
        ..methods.addAll(_parseMethods(element));
      ;

      if (annotClassConsts.isEmpty) {
        c.constructors.add(_generateConstructor());
        c.implements.add(refer(_generateTypeParameterizedName(element)));
      } else {
        c.extend = Reference(_generateTypeParameterizedName(element));
      }
    });

    final emitter = DartEmitter(useNullSafetySyntax: true);
    final code =
        DartFormatter().format([classBuilder.accept(emitter)].join('\n\n'));
    return code;
  }

  Iterable<Method> _parseMethods(ClassElement element) => <MethodElement>[
        ...element.methods,
        ...element.mixins.expand((i) => i.methods),
      ].where((m) {
        return m.isAbstract &&
            (m.returnType.isDartAsyncFuture || m.returnType.isDartAsyncStream);
      }).map((m) => _generateMethod(m)!);

  Method? _generateMethod(MethodElement m) {
    return Method((mm) {
      mm
        ..returns =
            refer(_getReturnType(m.type.returnType, withNullability: true))
        ..name = m.displayName
        ..types.addAll(m.typeParameters.map((e) => refer(e.name)))
        ..modifier = m.returnType.isDartAsyncFuture
            ? MethodModifier.async
            : MethodModifier.asyncStar
        ..annotations.add(const CodeExpression(Code('override')));

      /// required parameters
      mm.requiredParameters.addAll(
        m.parameters.where((it) => it.isRequiredPositional).map(
              (it) => Parameter(
                (p) => p
                  ..name = it.name
                  ..named = it.isNamed
                  ..type =
                      refer(it.type.getDisplayString(withNullability: true)),
              ),
            ),
      );

      /// optional positional or named parameters
      mm.optionalParameters.addAll(
        m.parameters.where((i) => i.isOptional || i.isRequiredNamed).map(
              (it) => Parameter(
                (p) => p
                  ..required = (it.isNamed &&
                      it.type.nullabilitySuffix == NullabilitySuffix.none &&
                      !it.hasDefaultValue)
                  ..name = it.name
                  ..named = it.isNamed
                  ..type =
                      refer(it.type.getDisplayString(withNullability: true))
                  ..defaultTo = it.defaultValueCode == null
                      ? null
                      : Code(it.defaultValueCode!),
              ),
            ),
      );
      mm.body = _generateRequest(m);
    });
  }

  String _getReturnType(DartType? returnType, {bool withNullability = false}) {
    final type = returnType!.alias!.element.displayName;

    if (returnType.alias!.element.displayName == 'ResponseFuture') {
      // Now, you can access type arguments (e.g., T) if needed
      final typeArguments = returnType.alias!.typeArguments;

      if (typeArguments.isNotEmpty) {
        return '$type<${typeArguments[0]}>';
        // Now, you have access to typeArgument, which represents T.
        // You can use typeArgument.displayName to get the name of T.
      }
    }
    return 'ResponseVoid';
  }

  Code _generateRequest(MethodElement m) {
    final parameters = m.parameters;

    var args = '';

    for (final parameter in parameters) {
      final parameterName = parameter.name;
      args = args + '$parameterName: $parameterName,';
    }

    final blocks = <Code>[];

    blocks.add(
      Code(
          '''

        try {
            final response = await $_clientVar.${m.displayName}($args);
            return Right(response);
          } on DioException catch (e) {
            if (e.type == DioExceptionType.receiveTimeout) {
              return Left(ConnectionFailure('Client Receive timeout.'));
            }
            if (e.type == DioExceptionType.connectionTimeout) {
              return Left(ConnectionFailure('Connection timeout.'));
            }
            return Left(ServerFailure(e.response!.data['detail']));
          } on Exception catch (e, stacktrace) {
            print(stacktrace);
            return Left(GenericFailure('Something went wrong.'));
          } on Error catch (e, stacktrace) {
            print(stacktrace);
            return Left(GenericFailure('Something went wrong.'));
          }

'''),
    );

    return Block.of(blocks);
  }

  String _generateTypeParameterizedName(TypeParameterizedElement element) =>
      element.displayName +
      (element.typeParameters.isNotEmpty
          ? '<${element.typeParameters.join(',')}>'
          : '');

  Field _buildClientFiled(String retrofitClient) => Field(
        (m) => m
          ..name = _clientVar
          ..type = refer(retrofitClient)
          ..modifier = FieldModifier.final$,
      );

  Constructor _generateConstructor({ConstructorElement? superClassConst}) =>
      Constructor((c) {
        c.requiredParameters.add(
          Parameter(
            (p) => p
              ..name = _clientVar
              ..toThis = true,
          ),
        );
      });
}
